"""
BuildPro CPMS — field material requisitions and the cross-system release
contract with the hardware store POS (Repo #1).

Flow:
    Site raises MaterialRequest  →  PM/Admin approves  →  ReleaseToken issued
    →  POS redeems the token against inventory  →  balance recorded in financials

ERD mapping:
    MATERIAL_REQUEST      → apps_requisitions.MaterialRequest
    MATERIAL_REQUEST_ITEM → apps_requisitions.MaterialRequestItem
    RELEASE_TOKEN         → apps_requisitions.ReleaseToken
    POS_SYNC_LOG          → apps_requisitions.PosSyncLog
"""

import secrets
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.utils import timezone

from ..projects.models import Project, Site


class RequestStatus(models.TextChoices):
    DRAFT = 'DRAFT', 'Draft'
    PENDING = 'PENDING', 'Pending Approval'
    APPROVED = 'APPROVED', 'Approved'
    PARTIALLY_APPROVED = 'PARTIALLY_APPROVED', 'Partially Approved'
    REJECTED = 'REJECTED', 'Rejected'
    RELEASED = 'RELEASED', 'Released to Site'
    CANCELLED = 'CANCELLED', 'Cancelled'


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
    """A field request for materials to be drawn from the hardware store."""

    request_no = models.CharField(max_length=32, unique=True)
    project = models.ForeignKey(
        Project,
        on_delete=models.PROTECT,
        related_name='material_requests',
    )
    site = models.ForeignKey(
        Site,
        on_delete=models.PROTECT,
        related_name='material_requests',
    )
    requested_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='material_requests',
    )
    status = models.CharField(
        max_length=24,
        choices=RequestStatus.choices,
        default=RequestStatus.DRAFT,
        db_index=True,
    )
    priority = models.CharField(
        max_length=8,
        choices=RequestPriority.choices,
        default=RequestPriority.NORMAL,
        db_index=True,
    )
    needed_date = models.DateField(null=True, blank=True)
    purpose = models.TextField(blank=True)
    notes = models.TextField(blank=True)

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
        ordering = ('-created_at',)
        verbose_name = 'Material Request'
        verbose_name_plural = 'Material Requests'
        indexes = [
            models.Index(fields=['status', 'priority']),
            models.Index(fields=['project', 'status']),
        ]

    def __str__(self):
        return f'{self.request_no} ({self.get_status_display()})'

    @property
    def is_editable(self):
        """Only unapproved requests may still be modified by field staff."""
        return self.status in (RequestStatus.DRAFT, RequestStatus.PENDING)

    @property
    def total_approved_value(self):
        return sum(
            (item.approved_value for item in self.items.all()),
            Decimal('0.00'),
        )

    def approve(self, user, partial=False):
        """Approve the request as a whole (or partially), stamping the reviewer."""
        self.status = (
            RequestStatus.PARTIALLY_APPROVED if partial else RequestStatus.APPROVED
        )
        self.reviewed_by = user
        self.reviewed_at = timezone.now()
        self.save(update_fields=['status', 'reviewed_by', 'reviewed_at', 'updated_at'])

    def reject(self, user, reason=''):
        self.status = RequestStatus.REJECTED
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
    """A single requested line item, reconciled against a POS SKU."""

    material_request = models.ForeignKey(
        MaterialRequest,
        on_delete=models.CASCADE,
        related_name='items',
    )
    item_sku = models.CharField(
        max_length=64,
        help_text='SKU from the POS catalogue (Repo #1).',
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
        help_text='Agreed cost per unit, used for budget vs actuals.',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('id',)
        verbose_name = 'Material Request Item'
        verbose_name_plural = 'Material Request Items'

    def __str__(self):
        return f'{self.material_request.request_no} / {self.item_sku}'

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