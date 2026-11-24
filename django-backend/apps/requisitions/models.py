"""
BuildPro CPMS — field material requisitions, purchasing and site receipts.

Phase 3 flow (contract `phase-3-procurement.md`):
    Site raises MaterialRequest (+ SiteCounts)
      → owner answers by placing a PurchaseOrder (own store | external)
      → site engineer confirms each Delivery on arrival
      → site inventory is *derived* (received − damaged − approved usage)

Own-store orders are also the CPMS side of the POS bridge: the order saves
`pos_request_id` / `pos_token` / `pos_sync_status` and a durable
`PosOutboxJob` row in the same transaction. No network call happens here —
the POS client and its retry worker are a separate task (3.1b). `released` on
a `PurchaseOrder` means **the order was sent to the own store**, never a
physical release or a delivery.

The pre-Phase-3 tables (`MaterialRequest` / `MaterialRequestItem` /
`ReleaseToken` / `PosSyncLog`) are the same tables, extended additively like
Phase 2's 0004/0005: legacy rows and columns are kept, the raw legacy request
status is copied into `legacy_status`, and nothing is deleted. The legacy
release-token workflow is retired from the API (the token was a 128-bit
bearer secret any authenticated caller could redeem), but its rows stay.

ERD mapping:
    MATERIAL_REQUEST      → apps_requisitions.MaterialRequest
    MATERIAL_REQUEST_ITEM → apps_requisitions.MaterialRequestItem
    SITE_COUNT            → apps_requisitions.SiteCount
    PURCHASE_ORDER        → apps_requisitions.PurchaseOrder
    PURCHASE_ORDER_ITEM   → apps_requisitions.PurchaseOrderItem
    DELIVERY              → apps_requisitions.Delivery
    DELIVERY_ITEM         → apps_requisitions.DeliveryItem
    POS_OUTBOX_JOB        → apps_requisitions.PosOutboxJob
    RELEASE_TOKEN         → apps_requisitions.ReleaseToken (legacy, kept)
    POS_SYNC_LOG          → apps_requisitions.PosSyncLog (legacy, kept)
"""

# Pyright here runs without django-stubs, so model fields and FKs are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

import secrets
import uuid
from datetime import timedelta
from decimal import Decimal
from pathlib import PurePosixPath

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.utils import timezone

from ..projects.models import Project, Site


def receipt_upload_path(instance, filename):
    """Private path for receipt evidence: `receipts/yyyy/mm/<uuid>.<ext>`.

    A caller-supplied name never reaches the filesystem (the Phase 2 upload
    rule); the sanitized original name is kept in `receipt_file_name` so the
    download URL can end in it.
    """
    suffix = PurePosixPath(str(filename)).suffix.lower()
    return f'receipts/{timezone.localdate():%Y/%m}/{uuid.uuid4().hex}{suffix}'


class RequestStatus(models.TextChoices):
    """Pre-Phase-3 request status codes, kept for legacy rows only.

    Migration 0004 copies the raw code into `MaterialRequest.legacy_status`
    and maps it onto `MaterialRequestStatus`; nothing new writes these values.
    """

    DRAFT = 'DRAFT', 'Draft'
    PENDING = 'PENDING', 'Pending Approval'
    APPROVED = 'APPROVED', 'Approved'
    PARTIALLY_APPROVED = 'PARTIALLY_APPROVED', 'Partially Approved'
    REJECTED = 'REJECTED', 'Rejected'
    RELEASED = 'RELEASED', 'Released to Site'
    CANCELLED = 'CANCELLED', 'Cancelled'


class MaterialRequestStatus(models.TextChoices):
    """Mirror of Flutter `MaterialRequestStatus` (`material_request.dart`)."""

    PENDING = 'pending', 'Pending'
    REJECTED = 'rejected', 'Rejected'
    ORDERED = 'ordered', 'Ordered'


class MaterialSource(models.TextChoices):
    """Mirror of Flutter `MaterialSource` (`material_source.dart`)."""

    OWN_STORE = 'own_store', 'Own store'
    EXTERNAL = 'external', 'Other supplier'


class PurchaseOrderStatus(models.TextChoices):
    """Mirror of Flutter `PurchaseOrderStatus` (`purchase_order.dart`).

    `RELEASED` means the order was sent to the own store (decision 04), not
    that anything left the counter: physical release and site receipt are
    separate facts (`Delivery`).
    """

    RELEASED = 'released', 'Released'
    PURCHASED = 'purchased', 'Bought'
    PARTIALLY_DELIVERED = 'partially_delivered', 'Partially delivered'
    DELIVERED = 'delivered', 'Delivered'
    CANCELLED = 'cancelled', 'Cancelled'


# Statuses in which the site may still receive material.
AWAITS_DELIVERY = frozenset({
    PurchaseOrderStatus.RELEASED,
    PurchaseOrderStatus.PURCHASED,
    PurchaseOrderStatus.PARTIALLY_DELIVERED,
})


class PosSyncStatus(models.TextChoices):
    """CPMS-side sync state of an own-store order, independent of POS status."""

    NOT_APPLICABLE = 'not_applicable', 'Not a POS order'
    PENDING_SYNC = 'pending_sync', 'Waiting for the POS'
    SYNCED = 'synced', 'Sent to the POS'
    FAILED = 'failed', 'Could not be sent'


class PosOutboxOperation(models.TextChoices):
    """What the POS worker (task 3.1b) must eventually do for this order."""

    IMPORT = 'import', 'Import the order at the store'
    CLOSE = 'close', 'Close the abandoned remainder'
    # Added in 3.1b: `pos-sync/` can also ask for a fresh read-back, because a
    # read never writes the snapshot (the contract forbids write-on-read).
    REFRESH = 'refresh', 'Refresh the store status'


class PosOutboxState(models.TextChoices):
    """Durable job state; only the worker (3.1b) moves a job past pending."""

    PENDING = 'pending', 'Pending'
    CANCELLED = 'cancelled', 'Cancelled before sending'
    DONE = 'done', 'Done'
    #: A permanent refusal (409/4xx, identity mismatch) or an exhausted bounded
    #: retry stops here: nothing retries it automatically until an owner asks.
    FAILED = 'failed', 'Needs review'


class RequestPriority(models.TextChoices):
    LOW = 'LOW', 'Low'
    NORMAL = 'NORMAL', 'Normal'
    HIGH = 'HIGH', 'High'
    URGENT = 'URGENT', 'Urgent'


class TokenStatus(models.TextChoices):
    ACTIVE = 'ACTIVE', 'Active'
    REDEEMED = 'REDEEMED', 'Redeemed'
    EXPIRED = 'EXPIRED', 'Expired'
    REVOKED = 'REVOKED', 'Revoked'


class MaterialRequest(models.Model):
    """A site engineer's request for material, answered by the owner's orders."""

    # `request_no` is the pre-Phase-3 unique number, kept for legacy rows. New
    # rows leave it null; the wire number is derived from the id (`MR-0004`).
    request_no = models.CharField(max_length=32, unique=True, null=True, blank=True)
    project = models.ForeignKey(
        Project,
        on_delete=models.PROTECT,
        related_name='material_requests',
    )
    # Legacy `site` column: kept, no longer required by the Phase 3 wire shape.
    site = models.ForeignKey(
        Site,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name='material_requests',
    )
    requested_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='material_requests',
    )
    # Budget category is chosen by the owner when ordering, not by the site.
    category = models.ForeignKey(
        'apps_projects.Category',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='material_requests',
    )
    status = models.CharField(
        max_length=24,
        choices=MaterialRequestStatus.choices,
        default=MaterialRequestStatus.PENDING,
        db_index=True,
    )
    priority = models.CharField(
        max_length=8,
        choices=RequestPriority.choices,
        default=RequestPriority.NORMAL,
        db_index=True,
    )
    # `needed_date` is the legacy name of the same fact; both are kept.
    needed_date = models.DateField(null=True, blank=True)
    needed_by = models.DateField(null=True, blank=True)
    purpose = models.TextField(blank=True)
    notes = models.TextField(blank=True)

    # The owner who first answered this request with an order.
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='approved_material_requests',
    )
    # The pre-Phase-3 status code, verbatim (migration 0004 fills it).
    legacy_status = models.CharField(
        max_length=24,
        blank=True,
        default='',
        help_text='Request status before Phase 3, kept for reconciliation.',
    )

    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='reviewed_material_requests',
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('-created_at', '-id')
        verbose_name = 'Material Request'
        verbose_name_plural = 'Material Requests'
        indexes = [
            models.Index(fields=['status', 'priority']),
            models.Index(fields=['project', 'status']),
        ]

    def __str__(self):
        return f'{self.number} ({self.get_status_display()})'

    @property
    def number(self):
        """The wire number the mock derives: `MR-{id padded to 4}`."""
        return f'MR-{int(self.pk or 0):04d}'

    @property
    def is_editable(self):
        """Only a pending request can still be rejected."""
        return self.status == MaterialRequestStatus.PENDING

    def reject(self, user, reason=''):
        """Refuse the request; the caller has already checked the status."""
        self.status = MaterialRequestStatus.REJECTED
        self.reviewed_by = user
        self.reviewed_at = timezone.now()
        self.rejection_reason = reason
        self.save(
            update_fields=[
                'status', 'reviewed_by', 'reviewed_at',
                'rejection_reason', 'updated_at',
            ]
        )


class MaterialRequestItem(models.Model):
    """One requested line, typed in the site engineer's own words.

    `quantity_requested` is the wire `quantity`; `quantity_approved` /
    `quantity_released` / `unit_cost` / `item_sku` are the pre-Phase-3 columns,
    kept for legacy rows and no longer written by Phase 3 code.
    """

    material_request = models.ForeignKey(
        MaterialRequest,
        on_delete=models.CASCADE,
        related_name='items',
    )
    item_sku = models.CharField(
        max_length=64,
        blank=True,
        default='',
        help_text='Legacy POS SKU; own-store lines are mapped by POS code now.',
    )
    description = models.CharField(max_length=255, blank=True)
    unit = models.CharField(max_length=32, default='pc')
    quantity_requested = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )
    quantity_approved = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
    )
    quantity_released = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
    )
    unit_cost = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
        help_text='Legacy agreed cost per unit; never serialized in Phase 3.',
    )
    # The order that covers this line, once the owner ticks it off.
    purchase_order = models.ForeignKey(
        'PurchaseOrder',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='covered_items',
    )
    planned_material = models.ForeignKey(
        'apps_projects.PlannedMaterial',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='request_items',
        help_text='Linked DUPA Section C planned material row, when picked from plan.',
    )
    is_unplanned = models.BooleanField(
        default=False,
        help_text='True when the foreman explicitly requested a material outside the DUPA.',
    )
    over_plan_reason = models.CharField(
        max_length=255,
        blank=True,
        default='',
        help_text='Justification when requesting an unplanned item or exceeding remaining DUPA qty.',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('id',)
        verbose_name = 'Material Request Item'
        verbose_name_plural = 'Material Request Items'

    def __str__(self):
        return f'{self.material_request_id} / {self.description}'

    @property
    def quantity(self):
        """The wire `quantity` (the legacy column holds the same fact)."""
        return self.quantity_requested

    @property
    def approved_value(self):
        return self.quantity_approved * self.unit_cost

    @property
    def outstanding_quantity(self):
        return self.quantity_approved - self.quantity_released


class ReleaseToken(models.Model):
    """A digital token authorising the POS to release materials to a site.

    The token is the cross-system handshake: CPMS issues it, the hardware
    store redeems it, and both sides keep the resulting reference.
    """

    material_request = models.ForeignKey(
        MaterialRequest,
        on_delete=models.CASCADE,
        related_name='release_tokens',
    )
    token = models.CharField(max_length=64, unique=True, db_index=True)
    status = models.CharField(
        max_length=16,
        choices=TokenStatus.choices,
        default=TokenStatus.ACTIVE,
        db_index=True,
    )
    issued_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='issued_release_tokens',
    )
    issued_at = models.DateTimeField(default=timezone.now)
    expires_at = models.DateTimeField()
    redeemed_at = models.DateTimeField(null=True, blank=True)
    redeemed_by_name = models.CharField(
        max_length=255,
        blank=True,
        help_text='Name of the store clerk who redeemed the token.',
    )
    pos_reference = models.CharField(
        max_length=64,
        blank=True,
        help_text='Sale / release reference returned by the POS.',
    )
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('-issued_at',)
        verbose_name = 'Release Token'
        verbose_name_plural = 'Release Tokens'
        indexes = [models.Index(fields=['status', 'expires_at'])]

    def __str__(self):
        return f'{self.token} ({self.get_status_display()})'

    @staticmethod
    def new_token():
        """Generate an unguessable, human-transcribable token string."""
        return secrets.token_hex(16).upper()

    @classmethod
    def issue_for(cls, material_request, user=None, ttl_hours=None):
        """Issue a fresh ACTIVE token for `material_request`.

        Retries on the (astronomically unlikely) token collision so the
        unique constraint is never surfaced as a 500 to the caller.
        """
        ttl = ttl_hours or settings.RELEASE_TOKEN_TTL_HOURS
        for _ in range(5):
            candidate = cls.new_token()
            if not cls.objects.filter(token=candidate).exists():
                break
        else:  # pragma: no cover - defensive, collision loop exhausted
            raise RuntimeError('Could not generate a unique release token.')

        return cls.objects.create(
            material_request=material_request,
            token=candidate,
            issued_by=user,
            issued_at=timezone.now(),
            expires_at=timezone.now() + timedelta(hours=ttl),
        )

    @property
    def is_expired(self):
        return timezone.now() >= self.expires_at

    @property
    def is_redeemable(self):
        """True only when the token is still valid for POS redemption."""
        return self.status == TokenStatus.ACTIVE and not self.is_expired

    def mark_redeemed(self, pos_reference='', redeemed_by_name=''):
        self.status = TokenStatus.REDEEMED
        self.redeemed_at = timezone.now()
        self.pos_reference = pos_reference
        if redeemed_by_name:
            self.redeemed_by_name = redeemed_by_name
        self.save(
            update_fields=[
                'status', 'redeemed_at', 'pos_reference',
                'redeemed_by_name', 'updated_at',
            ]
        )

    def revoke(self, reason=''):
        self.status = TokenStatus.REVOKED
        if reason:
            self.notes = f'{self.notes}\n{reason}'.strip()
        self.save(update_fields=['status', 'notes', 'updated_at'])


class PosSyncLog(models.Model):
    """Audit trail for every outbound call made to the POS backend."""

    material_request = models.ForeignKey(
        MaterialRequest,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='pos_sync_logs',
    )
    release_token = models.ForeignKey(
        ReleaseToken,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='pos_sync_logs',
    )
    endpoint = models.CharField(max_length=255)
    method = models.CharField(max_length=8, default='POST')
    status_code = models.PositiveIntegerField(null=True, blank=True)
    success = models.BooleanField(default=False, db_index=True)
    request_payload = models.JSONField(null=True, blank=True)
    response_payload = models.JSONField(null=True, blank=True)
    error_message = models.TextField(blank=True)
    duration_ms = models.PositiveIntegerField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ('-created_at',)
        verbose_name = 'POS Sync Log'
        verbose_name_plural = 'POS Sync Logs'
        indexes = [models.Index(fields=['success', 'created_at'])]

    def __str__(self):
        outcome = 'OK' if self.success else 'FAILED'
        return f'{self.method} {self.endpoint} → {self.status_code or "-"} ({outcome})'

# --------------------------------------------------------------------------
# Phase 3 — site counts, purchase orders, deliveries (contract
# `phase-3-procurement.md`; shapes mirror the Flutter models of the same name).
# --------------------------------------------------------------------------


class SiteCount(models.Model):
    """What the site engineer counted on site before asking for more.

    `expected` is the **server-calculated** on-hand snapshot; `counted` is the
    human figure. A variance is evidence for the owner, never a stock
    adjustment: inventory stays derived (`inventory.py`).
    """

    material_request = models.ForeignKey(
        MaterialRequest,
        on_delete=models.CASCADE,
        related_name='counts',
    )
    # Null for material bought outside the price list.
    material = models.ForeignKey(
        'apps_master_data.MaterialItem',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='site_counts',
    )
    name = models.CharField(max_length=200)
    unit = models.CharField(max_length=32, default='pc')
    expected = models.DecimalField(max_digits=12, decimal_places=2)
    counted = models.DecimalField(max_digits=12, decimal_places=2)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('id',)
        verbose_name = 'Site Count'
        verbose_name_plural = 'Site Counts'

    def __str__(self):
        return f'{self.name}: {self.counted} (expected {self.expected})'


class PurchaseOrder(models.Model):
    """The owner's answer to a request: an own-store order or a purchase.

    Own-store orders also carry the POS bridge fields so enabling the bridge
    (task 3.1b) needs no schema change. `released` means the order was sent to
    the own store, never that material left the counter.
    """

    po_no = models.CharField(
        max_length=32,
        unique=True,
        null=True,
        blank=True,
        help_text='Set once after insert: PO-{year}-{id padded to 4}.',
    )
    project = models.ForeignKey(
        Project,
        on_delete=models.PROTECT,
        related_name='purchase_orders',
    )
    material_request = models.ForeignKey(
        MaterialRequest,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='purchase_orders',
    )
    category = models.ForeignKey(
        'apps_projects.Category',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='purchase_orders',
    )
    supplier = models.ForeignKey(
        'apps_master_data.Supplier',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='purchase_orders',
    )
    store_name = models.CharField(max_length=200, blank=True, default='')
    source = models.CharField(
        max_length=16,
        choices=MaterialSource.choices,
        default=MaterialSource.EXTERNAL,
        db_index=True,
    )
    status = models.CharField(
        max_length=24,
        choices=PurchaseOrderStatus.choices,
        default=PurchaseOrderStatus.RELEASED,
        db_index=True,
    )
    total_amount = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
    )
    delivery_address = models.CharField(max_length=255, blank=True, default='')
    or_number = models.CharField(max_length=64, blank=True, default='')

    # Receipt evidence: private file + the sanitized display name (Phase 2
    # upload conventions). `receipt_photo_url` is built from these, never stored
    # as a caller-supplied URL.
    receipt_file = models.FileField(
        upload_to=receipt_upload_path, null=True, blank=True,
    )
    receipt_file_name = models.CharField(max_length=255, blank=True, default='')
    receipt_content_type = models.CharField(max_length=64, blank=True, default='')

    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='purchase_orders',
    )

    # --- POS bridge (decision 04) — minted once, never regenerated ----------
    pos_request_id = models.UUIDField(null=True, blank=True, unique=True)
    pos_token = models.UUIDField(
        null=True,
        blank=True,
        help_text='Bearer UUID for the POS import. Never serialized.',
    )
    pos_sync_status = models.CharField(
        max_length=16,
        choices=PosSyncStatus.choices,
        default=PosSyncStatus.NOT_APPLICABLE,
        db_index=True,
    )
    pos_expected_amount = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        null=True,
        blank=True,
        help_text='POS budget estimate; never invoice evidence (blocker 1).',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('-created_at', '-id')
        verbose_name = 'Purchase Order'
        verbose_name_plural = 'Purchase Orders'
        indexes = [
            models.Index(fields=['project', 'status']),
            models.Index(fields=['source', 'pos_sync_status']),
        ]

    def __str__(self):
        return f'{self.po_no or f"PO#{self.pk}"} ({self.get_status_display()})'


class PurchaseOrderItem(models.Model):
    """One ordered line; `unit_price` is finance-only on the wire."""

    purchase_order = models.ForeignKey(
        PurchaseOrder,
        on_delete=models.CASCADE,
        related_name='items',
    )
    material = models.ForeignKey(
        'apps_master_data.MaterialItem',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='purchase_order_items',
    )
    description = models.CharField(max_length=255)
    unit = models.CharField(max_length=32, default='pc')
    quantity = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )
    unit_price = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('id',)
        verbose_name = 'Purchase Order Item'
        verbose_name_plural = 'Purchase Order Items'

    def __str__(self):
        return f'{self.description} x{self.quantity}'

    @property
    def amount(self):
        return self.quantity * self.unit_price


class Delivery(models.Model):
    """One delivery receipt against a purchase order."""

    purchase_order = models.ForeignKey(
        PurchaseOrder,
        on_delete=models.CASCADE,
        related_name='deliveries',
    )
    received_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='confirmed_deliveries',
    )
    received_at = models.DateTimeField(default=timezone.now)

    receipt_file = models.FileField(
        upload_to=receipt_upload_path, null=True, blank=True,
    )
    receipt_file_name = models.CharField(max_length=255, blank=True, default='')
    receipt_content_type = models.CharField(max_length=64, blank=True, default='')

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('-received_at', '-id')
        verbose_name = 'Delivery'
        verbose_name_plural = 'Deliveries'

    def __str__(self):
        return f'Delivery #{self.pk} for PO {self.purchase_order_id}'


class DeliveryItem(models.Model):
    """Received / damaged quantity on one PO line. Damaged is part of received."""

    delivery = models.ForeignKey(
        Delivery,
        on_delete=models.CASCADE,
        related_name='items',
    )
    purchase_order_item = models.ForeignKey(
        PurchaseOrderItem,
        on_delete=models.PROTECT,
        related_name='delivery_items',
    )
    qty_received = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.00'))],
    )
    qty_damaged = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('id',)
        verbose_name = 'Delivery Item'
        verbose_name_plural = 'Delivery Items'

    def __str__(self):
        return f'{self.purchase_order_item_id}: {self.qty_received}'

    @property
    def qty_good(self):
        """Usable quantity: damaged goods never enter inventory or costing."""
        return self.qty_received - self.qty_damaged


class PosOutboxJob(models.Model):
    """Durable record of POS work owed for an order (no worker yet — 3.1b).

    Saved in the same transaction as the order itself, so an own-store order
    can never exist without the intent to send it, and a retry is never
    reconstructed from mutable master data (the payload is a snapshot).
    """

    purchase_order = models.ForeignKey(
        PurchaseOrder,
        on_delete=models.PROTECT,
        related_name='outbox_jobs',
    )
    operation = models.CharField(
        max_length=16,
        choices=PosOutboxOperation.choices,
        default=PosOutboxOperation.IMPORT,
    )
    # `{operation}:{pos_request_id}` — one durable row per order per operation.
    idempotency_key = models.CharField(max_length=120, unique=True)
    payload = models.JSONField(default=dict, blank=True)
    state = models.CharField(
        max_length=16,
        choices=PosOutboxState.choices,
        default=PosOutboxState.PENDING,
        db_index=True,
    )
    attempts = models.PositiveIntegerField(default=0)
    next_attempt_at = models.DateTimeField(null=True, blank=True)
    last_error = models.TextField(blank=True, default='')
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='pos_outbox_jobs',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('id',)
        verbose_name = 'POS Outbox Job'
        verbose_name_plural = 'POS Outbox Jobs'
        indexes = [models.Index(fields=['state', 'next_attempt_at'])]

    def __str__(self):
        return f'{self.operation} PO#{self.purchase_order_id} ({self.state})'


class PosRequestSnapshot(models.Model):
    """The last POS read-back for one order, kept apart from CPMS's own status.

    `pos_status` is the store's **raw** string (`WAITING`, `ACCEPTED`,
    `PARTIALLY_RELEASED`, a legacy state, …) and is never folded into a CPMS
    enum: an unknown upstream state must stay visible, not be guessed. The
    amount is the store's live budget estimate (`expected_amount`, nullable —
    null means unknown, never free goods), never invoice evidence.

    One row per order; `stale` says the last refresh attempt failed, and a read
    older than `POS_STATUS_STALE_AFTER_SECONDS` is reported stale too.
    """

    purchase_order = models.OneToOneField(
        PurchaseOrder,
        on_delete=models.CASCADE,
        related_name='pos_snapshot',
    )
    pos_status = models.CharField(max_length=32, blank=True, default='')
    decline_reason = models.TextField(blank=True, default='')
    expected_amount = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        null=True,
        blank=True,
        help_text='The store\'s budget estimate; null means unknown.',
    )
    #: `[{code, requested, released, outstanding, available, decline_reason}]`
    lines = models.JSONField(default=list, blank=True)
    #: Human note for the UI (a refusal reason). Never a token or a raw body.
    detail = models.TextField(blank=True, default='')
    last_checked_at = models.DateTimeField(null=True, blank=True)
    stale = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'POS Request Snapshot'
        verbose_name_plural = 'POS Request Snapshots'

    def __str__(self):
        return f'PO#{self.purchase_order_id}: {self.pos_status or "unknown"}'
