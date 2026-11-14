"""Transactional procurement writes (Phase 3, task 3.1a).

Everything that changes a request, an order or a delivery happens here inside
`transaction.atomic()`, so the business rows, the audit row, the notification
and — for an own-store order — the durable `PosOutboxJob` all land together or
not at all.

Four ordering rules this file keeps:

1. **No write before a refusal.** Every id, number, file and role is resolved
   and validated first, so a bad PO line or an unreadable receipt cannot leave
   a half-saved order (or an orphaned file) behind.
2. **Locks before totals.** Receipts and order coverage re-read their rows
   under `select_for_update()`, so two site engineers cannot both receive the
   last 5 bags, and two orders cannot both cover the same requested item.
3. **Decimal arithmetic only.** Quantities are `Decimal(12,2)`; prices and
   totals are `Decimal`; no float tolerance, no silent rounding.
4. **The POS is not called.** An own-store order mints its identity, saves
   `pos_sync_status = pending_sync` and enqueues the outbox row. The client and
   retry worker are task 3.1b.

`released` on an order means "sent to the own store", never a physical release:
only a `Delivery` proves material arrived on site.
"""

# Pyright runs without django-stubs, so model managers/FKs are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportOptionalMemberAccess=false

import json
import uuid
from datetime import date
from decimal import Decimal
from typing import NoReturn

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import NotFound

from ..master_data.models import MaterialItem, Supplier
from ..projects import scoping
from ..projects.models import Category, ProjectStatus, RoleOnProject
from ..projects.rules import NotAllowed, RuleRefused
from ..projects.services import notify_owners, notify_project_role
from ..site_reports import uploads
from ..users import capabilities
from ..users.models import Role, User
from ..users.services import notify, record
from . import rules
from .inventory import committed_amount, inventory_key, site_inventory
from .models import (
    AWAITS_DELIVERY,
    Delivery,
    DeliveryItem,
    MaterialRequest,
    MaterialRequestItem,
    MaterialRequestStatus,
    MaterialSource,
    PosOutboxJob,
    PosOutboxOperation,
    PosOutboxState,
    PosSyncStatus,
    PurchaseOrder,
    PurchaseOrderItem,
    PurchaseOrderStatus,
    SiteCount,
)

ZERO = Decimal('0.00')
REQUESTS_LINK = '/material-requests'  # AppRoutes.materialRequests
ORDERS_LINK = '/purchase-orders'      # AppRoutes.purchaseOrders
DELIVERIES_LINK = '/deliveries'       # AppRoutes.deliveries


def _text(value):
    return '' if value is None else str(value).strip()


def _refuse(message) -> NoReturn:
    raise RuleRefused(message)


def _json_list(value, message=rules.BAD_LINES, allow_scalars=False):
    """A JSON array from a JSON body or a multipart field, or a `400`."""
    if value is None:
        return []
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return []
        try:
            value = json.loads(text)
        except ValueError:
            _refuse(message)
    if not isinstance(value, list):
        _refuse(message)
    if allow_scalars:
        return value
    if any(not isinstance(row, dict) for row in value):
        _refuse(message)
    return value


def _quantity(raw):
    """A positive order quantity, with the mock's refusal texts."""
    number = rules.as_decimal(raw)
    if number is None:
        _refuse(rules.QUANTITY_POSITIVE)
    if number != number.quantize(rules.QUANTITY_PLACES):
        _refuse(rules.PRECISION)
    if abs(number) > rules.QUANTITY_MAX:
        _refuse(rules.TOO_LARGE)
    if number <= 0:
        _refuse(rules.QUANTITY_POSITIVE)
    return number


def _counted(raw):
    """A counted quantity: zero or more, 2 decimal places at most."""
    number = rules.as_decimal(raw)
    if number is None:
        _refuse(rules.COUNT_INVALID)
    if number != number.quantize(rules.QUANTITY_PLACES):
        _refuse(rules.PRECISION)
    if abs(number) > rules.QUANTITY_MAX:
        _refuse(rules.TOO_LARGE)
    if number < 0:
        _refuse(rules.COUNT_INVALID)
    return number


# A `BigAutoField` id; anything outside it cannot name a material at all.
MAX_PK = 2 ** 63 - 1


def _count_material(raw_id):
    """The price-list id a count names: absent → `None`, junk/unknown → `400`.

    A count may name material the price list does not hold (free text only),
    but a *supplied* id must be an existing material id — never a junk string
    (a `DataError` on insert) or an unknown id (a `ForeignKeyViolation`), both
    of which used to surface as HTTP 500.
    """
    if raw_id in (None, ''):
        return None
    try:
        material_id = int(str(raw_id))
    except (TypeError, ValueError):
        _refuse(rules.COUNT_MATERIAL)
    if not 0 < material_id <= MAX_PK:
        _refuse(rules.COUNT_MATERIAL)
    if not MaterialItem.objects.filter(pk=material_id).exists():
        _refuse(rules.COUNT_MATERIAL)
    return material_id


def _unit_price(raw):
    """A price of zero or more, 2 decimal places at most."""
    number = rules.as_decimal(raw)
    if number is None:
        _refuse(rules.UNIT_PRICE)
    if number != number.quantize(rules.QUANTITY_PLACES):
        _refuse(rules.PRECISION)
    if abs(number) > rules.MONEY_MAX:
        _refuse(rules.TOO_LARGE)
    if number < 0:
        _refuse(rules.UNIT_PRICE)
    return number


def _received(raw):
    """A receipt quantity: zero or more (negatives are their own refusal)."""
    number = rules.as_decimal(raw)
    if number is None:
        _refuse(rules.NEGATIVE_QUANTITY)
    if number != number.quantize(rules.QUANTITY_PLACES):
        _refuse(rules.PRECISION)
    if abs(number) > rules.QUANTITY_MAX:
        _refuse(rules.TOO_LARGE)
    if number < 0:
        _refuse(rules.NEGATIVE_QUANTITY)
    return number


def _serve_date(raw, message):
    if raw in (None, ''):
        _refuse(message)
    try:
        return date.fromisoformat(str(raw)[:10])
    except ValueError:
        _refuse(message)


def _require_role(role, wanted, message):
    if role != wanted:
        raise NotAllowed(message)


def _require_accepted(project, user, role_on_project, message):
    if not scoping.has_accepted_assignment(project, user, role_on_project):
        raise NotAllowed(message)


def _project_ongoing(project, what):
    """The mock's `requireOngoing` sentence (site reports use the same shape)."""
    if project.status != ProjectStatus.ONGOING:
        label = ProjectStatus(project.status).label
        _refuse(
            f'{what} can be added only while the project is Ongoing (it is {label}).'
        )


# --------------------------------------------------------------------------
# Material requests
# --------------------------------------------------------------------------

def create_request(user, role, project, data):
    """`POST material-requests/` — the site engineer asks for material."""
    _require_role(role, Role.SITE_ENGINEER, rules.NOT_THE_ENGINEER)
    _require_accepted(project, user, RoleOnProject.SITE_ENGINEER, rules.NOT_THE_ENGINEER)
    _project_ongoing(project, 'Material requests')

    needed_by = _serve_date(data.get('needed_by'), rules.NEEDED_BY_REQUIRED)
    if needed_by < timezone.localdate():
        _refuse(rules.NEEDED_BY_PAST)

    lines = _json_list(data.get('items'))
    if not lines:
        _refuse(rules.ADD_AN_ITEM)
    items = []
    for row in lines:
        description = _text(row.get('description'))
        if not description:
            _refuse(rules.ENTER_ITEM)
        items.append({
            'description': description,
            'unit': _text(row.get('unit')),
            'quantity': _quantity(row.get('quantity')),
        })

    # Every material the system thinks is on site must be counted first, and
    # the expected figure is the server's own snapshot (a stale one is a
    # retryable 409, never trusted).
    on_hand = {
        inventory_key(line['material_id'], line['name']): line
        for line in site_inventory(project)
    }
    submitted = {}
    for row in _json_list(data.get('counts'), rules.COUNT_INVALID):
        material_id = _count_material(row.get('material_id'))
        submitted[inventory_key(material_id, row.get('name'))] = {
            **row, 'material_id': material_id,
        }
    counts = []
    for key, line in on_hand.items():
        if line['on_hand'] == 0:
            continue
        row = submitted.get(key)
        if row is None:
            _refuse(rules.count_first(line['name']))
        counted = _counted(row.get('counted'))
        claimed = row.get('expected')
        if claimed is not None and rules.as_decimal(claimed) != line['on_hand']:
            raise rules.StaleSiteCount()
        counts.append({
            'material_id': line['material_id'],
            'name': line['name'],
            'unit': line['unit'],
            'expected': line['on_hand'],
            'counted': counted,
        })
    # Counts for material the system does not track are kept as evidence.
    for key, row in submitted.items():
        if key in on_hand:
            continue
        name = _text(row.get('name'))
        if not name:
            _refuse(rules.COUNT_INVALID)
        counts.append({
            'material_id': row['material_id'],
            'name': name,
            'unit': _text(row.get('unit')),
            'expected': _counted(row.get('expected')) if row.get('expected') is not None else ZERO,
            'counted': _counted(row.get('counted')),
        })

    with transaction.atomic():
        material_request = MaterialRequest.objects.create(
            project=project,
            requested_by=user,
            status=MaterialRequestStatus.PENDING,
            needed_by=needed_by,
        )
        material_request.request_no = material_request.number
        material_request.save(update_fields=['request_no'])
        MaterialRequestItem.objects.bulk_create([
            MaterialRequestItem(
                material_request=material_request,
                description=row['description'],
                unit=row['unit'],
                quantity_requested=row['quantity'],
            )
            for row in items
        ])
        for row in counts:
            SiteCount.objects.create(
                material_request=material_request,
                material_id=row['material_id'],
                name=row['name'],
                unit=row['unit'],
                expected=row['expected'],
                counted=row['counted'],
            )
        record(
            user, 'material_request_created', 'material_request', material_request.pk,
            {'items': len(items), 'counted': len(counts)},
        )
        notify_owners(
            project,
            f'{material_request.number} for {project.code} is waiting for you.',
            link=f'{REQUESTS_LINK}/{material_request.pk}',
            type='material_request',
        )
    return material_request


def reject_request(user, role, material_request, data):
    """`POST material-requests/{id}/reject/` — the assigned owner turns it down."""
    _require_role(role, Role.OWNER, rules.NOT_THE_PM)
    _require_accepted(
        material_request.project, user, RoleOnProject.OWNER, rules.NOT_THE_PM,
    )
    if material_request.status != MaterialRequestStatus.PENDING:
        _refuse(
            rules.cannot_reject(
                MaterialRequestStatus(material_request.status).label, role,
            )
        )
    reason = _text(data.get('reason'))
    if not reason:
        _refuse(rules.REJECT_REASON)

    with transaction.atomic():
        locked = MaterialRequest.objects.select_for_update().get(
            pk=material_request.pk,
        )
        if locked.status != MaterialRequestStatus.PENDING:
            _refuse(
                rules.cannot_reject(
                    MaterialRequestStatus(locked.status).label, role,
                )
            )
        locked.reject(user, reason=reason)
        record(
            user, 'material_request_rejected', 'material_request', locked.pk,
            {'reason': reason},
        )
        notify(
            locked.requested_by, 'material_request',
            f'Your {locked.number} was rejected: {reason}',
            link=f'{REQUESTS_LINK}/{locked.pk}',
        )
    return locked


# --------------------------------------------------------------------------
# Purchase orders
# --------------------------------------------------------------------------

def _own_store_supplier():
    """The single own-store supplier (0 or many is a setup refusal)."""
    suppliers = list(
        Supplier.objects.filter(is_own_store=True).order_by('id')[:2]
    )
    if not suppliers:
        _refuse(rules.NO_OWN_STORE)
    if len(suppliers) > 1:
        _refuse(rules.AMBIGUOUS_OWN_STORE)
    return suppliers[0]


def _resolve_material(raw_id):
    """A price-list material by id, or `None` when the id is absent/junk."""
    try:
        material_id = int(str(raw_id))
    except (TypeError, ValueError):
        return None
    return MaterialItem.objects.filter(pk=material_id).first()


def place_order(user, role, project, data, upload=None):
    """`POST purchase-orders/` — the owner answers a request.

    Own-store: one own-store supplier, POS codes on every line, a delivery
    address, `pos_sync_status = pending_sync`, and a durable outbox row — all
    in the same transaction. External: store name, OR number and the private
    receipt photo, and the order never touches the POS.
    """
    _require_role(role, Role.OWNER, rules.NOT_THE_PM)
    _require_accepted(project, user, RoleOnProject.OWNER, rules.NOT_THE_PM)

    try:
        request_id = int(str(data.get('request_id')))
    except (TypeError, ValueError):
        _refuse('Request not found.')
    material_request = MaterialRequest.objects.filter(
        pk=request_id, project=project,
    ).select_related('project', 'requested_by').first()
    if material_request is None:
        raise NotFound()
    if material_request.status == MaterialRequestStatus.REJECTED:
        _refuse(rules.REQUEST_REJECTED)

    try:
        category_id = int(str(data.get('category_id')))
    except (TypeError, ValueError):
        _refuse(rules.CHOOSE_CATEGORY)
    category = Category.objects.filter(pk=category_id, project=project).first()
    if category is None:
        _refuse(rules.CHOOSE_CATEGORY)

    lines = _json_list(data.get('lines'))
    if not lines:
        _refuse(rules.ADD_A_MATERIAL)
    order_lines = []
    for row in lines:
        description = _text(row.get('description'))
        if not description:
            _refuse(rules.ENTER_MATERIAL)
        order_lines.append({
            'material': _resolve_material(row.get('material_id')),
            'description': description,
            'unit': _text(row.get('unit')),
            'quantity': _quantity(row.get('quantity')),
            'unit_price': _unit_price(row.get('unit_price')),
        })

    covers = _json_list(data.get('covers_item_ids'), rules.NOT_ON_REQUEST, allow_scalars=True)
    try:
        cover_ids = [int(str(row.get('id') if isinstance(row, dict) else row)) for row in covers]
    except (TypeError, ValueError):
        _refuse(rules.NOT_ON_REQUEST)
    if len(set(cover_ids)) != len(cover_ids):
        _refuse(rules.NOT_ON_REQUEST)
    # Membership is checked before any write; coverage itself is re-read under
    # the locks inside the transaction, because a concurrent order can cover
    # the same item between this check and the update.
    for item_id in cover_ids:
        if not MaterialRequestItem.objects.filter(
            pk=item_id, material_request=material_request,
        ).exists():
            _refuse(rules.NOT_ON_REQUEST)

    source = _text(data.get('source'))
    if source not in MaterialSource.values:
        _refuse('Choose where the material comes from.')
    own_store = source == MaterialSource.OWN_STORE

    supplier = None
    store_name = _text(data.get('store_name'))
    or_number = _text(data.get('or_number'))
    delivery_address = _text(data.get('delivery_address'))
    receipt = None
    if own_store:
        if not delivery_address:
            _refuse(rules.DELIVERY_ADDRESS)
        if any(line['material'] is None for line in order_lines):
            _refuse(rules.OWN_STORE_CATALOG)
        supplier = _own_store_supplier()
        if any(not _text(line['material'].pos_code) for line in order_lines):
            _refuse(rules.MISSING_POS_CODE)
    else:
        if not store_name:
            _refuse(rules.ENTER_STORE_NAME)
        if not or_number:
            _refuse(rules.ENTER_OR_NUMBER)
        if upload is None:
            _refuse(rules.ATTACH_RECEIPT)
        # Validate the file before any row is written.
        receipt = (upload, *uploads.check_photo(upload))

    total = sum(
        (line['quantity'] * line['unit_price'] for line in order_lines), ZERO,
    )

    order = None
    attached = False
    try:
        with transaction.atomic():
            locked = MaterialRequest.objects.select_for_update().get(
                pk=material_request.pk,
            )
            if locked.status == MaterialRequestStatus.REJECTED:
                _refuse(rules.REQUEST_REJECTED)
            # Coverage is re-read here, not only before the transaction: two
            # orders can both pass the early check, and the later `.update()`
            # would silently steal the item. Lock the request first, then its
            # item rows, so exactly one order covers each item.
            if cover_ids:
                covered = {
                    row.pk: row
                    for row in MaterialRequestItem.objects.select_for_update().filter(
                        material_request=locked, pk__in=cover_ids,
                    )
                }
                for item_id in cover_ids:
                    row = covered.get(item_id)
                    if row is None:
                        _refuse(rules.NOT_ON_REQUEST)
                    if row.purchase_order_id is not None:
                        _refuse(rules.already_covered(row.description))
            order = PurchaseOrder.objects.create(
                project=project,
                material_request=locked,
                category=category,
                supplier=supplier,
                store_name='' if own_store else store_name,
                source=source,
                status=(
                    PurchaseOrderStatus.RELEASED if own_store
                    else PurchaseOrderStatus.PURCHASED
                ),
                total_amount=total,
                delivery_address=delivery_address,
                or_number='' if own_store else or_number,
                approved_by=user,
                pos_sync_status=(
                    PosSyncStatus.PENDING_SYNC if own_store
                    else PosSyncStatus.NOT_APPLICABLE
                ),
                pos_request_id=uuid.uuid4() if own_store else None,
                pos_token=uuid.uuid4() if own_store else None,
            )
            order.po_no = f'PO-{timezone.localdate():%Y}-{order.pk:04d}'
            order.save(update_fields=['po_no'])
            PurchaseOrderItem.objects.bulk_create([
                PurchaseOrderItem(
                    purchase_order=order,
                    material=line['material'],
                    description=line['description'],
                    unit=line['unit'],
                    quantity=line['quantity'],
                    unit_price=line['unit_price'],
                )
                for line in order_lines
            ])
            if receipt is not None:
                file_obj, display_name, extension = receipt
                order.receipt_file.save(display_name, file_obj, save=False)
                order.receipt_file_name = display_name
                order.receipt_content_type = uploads.content_type(extension)
                order.save(update_fields=[
                    'receipt_file', 'receipt_file_name', 'receipt_content_type',
                ])
                attached = True
            if cover_ids:
                MaterialRequestItem.objects.filter(
                    pk__in=cover_ids,
                ).update(purchase_order=order)
            locked.status = MaterialRequestStatus.ORDERED
            locked.category = category
            if locked.approved_by_id is None:
                locked.approved_by = user
            locked.save(update_fields=['status', 'category', 'approved_by', 'updated_at'])
            if own_store:
                _enqueue_import(order, user)
            record(
                user,
                'purchase_order_created' if own_store else 'purchase_logged',
                'purchase_order', order.pk,
                # Ids, counts and source only: `admin` is not a finance role
                # but reads this audit trail, and the contract omits monetary
                # data from non-finance responses. Never store the total here.
                {
                    'request_id': locked.pk,
                    'lines': len(order_lines),
                    'source': source,
                    'pos_request_id': str(order.pos_request_id) if own_store else None,
                },
            )
            notify(
                locked.requested_by, 'material_request',
                (
                    f'Your {locked.number} was ordered from the own store.'
                    if own_store
                    else f'Your {locked.number} was bought at {store_name}.'
                ),
                link=f'{REQUESTS_LINK}/{locked.pk}',
            )
            notify_project_role(
                project, RoleOnProject.SITE_ENGINEER,
                (
                    f'{order.po_no} was bought at {store_name}. Confirm the '
                    'delivery on arrival.'
                    if not own_store
                    else f'{order.po_no} is released to the own store. Confirm '
                    'the delivery on arrival.'
                ),
                type='purchase_order',
                # AppRoutes.deliveryConfirm(order) — a real GoRouter route.
                link=f'{DELIVERIES_LINK}/confirm/{order.pk}',
            )
    except Exception:
        if attached and order is not None and order.receipt_file:
            order.receipt_file.delete(save=False)
        raise
    return order


def _enqueue_import(order, user):
    """Durable POS import intent; the payload is a snapshot, never a re-read."""
    items = list(order.items.select_related('material'))
    payload = {
        'cpms_request_id': order.po_no,
        'project': {
            'cpms_project_id': order.project.code,
            'name': order.project.name,
            'payer': order.supplier.pos_payer_id if order.supplier else None,
        },
        'requester_name': (
            order.material_request.requested_by.full_name
            if order.material_request else ''
        ),
        'approver_name': user.full_name,
        'items': [
            {'code': item.material.pos_code, 'quantity': f'{item.quantity:f}'}
            for item in items
        ],
    }
    PosOutboxJob.objects.create(
        purchase_order=order,
        operation=PosOutboxOperation.IMPORT,
        idempotency_key=f'import:{order.pos_request_id}',
        payload=payload,
        created_by=user,
    )


def cancel_order(user, role, order):
    """`POST purchase-orders/{id}/cancel/` — refuse once anything arrived."""
    _require_role(role, Role.OWNER, rules.NOT_THE_PM)
    _require_accepted(order.project, user, RoleOnProject.OWNER, rules.NOT_THE_PM)

    with transaction.atomic():
        # A nullable FK cannot be `select_related` under FOR UPDATE (Postgres
        # refuses FOR UPDATE on the nullable side of an outer join).
        locked = PurchaseOrder.objects.select_for_update().get(pk=order.pk)
        if locked.deliveries.exists():
            _refuse(rules.PO_HAS_DELIVERIES)
        if locked.or_number:
            _refuse(rules.PAID_AT_STORE)
        if locked.status == PurchaseOrderStatus.CANCELLED:
            return locked

        material_request = locked.material_request
        if material_request is not None:
            MaterialRequest.objects.select_for_update().filter(
                pk=material_request.pk,
            ).first()

        locked.status = PurchaseOrderStatus.CANCELLED
        locked.save(update_fields=['status', 'updated_at'])
        MaterialRequestItem.objects.filter(purchase_order=locked).update(
            purchase_order=None,
        )
        if material_request is not None and not PurchaseOrder.objects.filter(
            material_request=material_request,
        ).exclude(status=PurchaseOrderStatus.CANCELLED).exists():
            # Nothing live answers the request any more: it needs the owner.
            MaterialRequest.objects.filter(pk=material_request.pk).update(
                status=MaterialRequestStatus.PENDING,
            )
        _settle_pos_on_cancel(locked)
        record(
            user, 'purchase_order_cancelled', 'purchase_order', locked.pk,
            {'source': locked.source, 'pos_request_id': str(locked.pos_request_id or '')},
        )
    return locked


def _settle_pos_on_cancel(order):
    """Record what the eventual POS close must do (no network here).

    An import that was never sent can be dropped; an order the POS already
    knows about keeps a close intent, because abandoning the remainder must
    never be reported as a reversal of a release or a debt.
    """
    if order.pos_sync_status == PosSyncStatus.PENDING_SYNC:
        order.outbox_jobs.filter(
            operation=PosOutboxOperation.IMPORT,
            state=PosOutboxState.PENDING,
        ).update(state=PosOutboxState.CANCELLED, updated_at=timezone.now())
        order.pos_sync_status = PosSyncStatus.NOT_APPLICABLE
        order.save(update_fields=['pos_sync_status', 'updated_at'])
        return
    if order.pos_sync_status in (PosSyncStatus.SYNCED, PosSyncStatus.FAILED):
        PosOutboxJob.objects.get_or_create(
            idempotency_key=f'close:{order.pos_request_id}',
            defaults={
                'purchase_order': order,
                'operation': PosOutboxOperation.CLOSE,
                'payload': {'cpms_request_id': order.po_no},
                'created_by': order.approved_by,
            },
        )


# --------------------------------------------------------------------------
# Deliveries
# --------------------------------------------------------------------------

def confirm_delivery(user, role, order, data, upload=None):
    """`POST purchase-orders/{id}/deliveries/` — the site engineer signs for it.

    Receipts are the only proof material reached the site, so the PO and its
    lines are locked and the cumulative total is re-checked under the lock.
    """
    _require_role(role, Role.SITE_ENGINEER, rules.NOT_THE_SE)
    _require_accepted(order.project, user, RoleOnProject.SITE_ENGINEER, rules.NOT_THE_SE)

    lines = _json_list(data.get('lines'))
    receipt = None
    if upload is not None:
        receipt = (upload, *uploads.check_photo(upload))

    delivery = None
    attached = False
    try:
        with transaction.atomic():
            locked = PurchaseOrder.objects.select_for_update().get(pk=order.pk)
            if locked.status not in AWAITS_DELIVERY:
                _refuse(
                    rules.nothing_to_receive(
                        PurchaseOrderStatus(locked.status).label,
                    )
                )
            items = {
                item.pk: item
                for item in locked.items.select_for_update().all()
            }
            prepared = []
            seen = set()
            already = _received_totals(locked)
            # The mock refuses an empty receipt before it looks at the lines.
            rows = [
                (row, _received(row.get('received')), _received(row.get('damaged')))
                for row in lines
            ]
            if not any(received > 0 for _, received, _ in rows):
                _refuse(rules.ENTER_RECEIVED)
            for row, received, damaged in rows:
                try:
                    po_item_id = int(str(row.get('po_item_id')))
                except (TypeError, ValueError):
                    _refuse(rules.UNKNOWN_PO_LINE)
                if po_item_id in seen:
                    _refuse(rules.DUPLICATE_PO_LINE)
                seen.add(po_item_id)
                item = items.get(po_item_id)
                if item is None:
                    _refuse(rules.UNKNOWN_PO_LINE)
                if damaged > received:
                    _refuse(rules.DAMAGED_GT_RECEIVED)
                left = item.quantity - already.get(po_item_id, ZERO)
                if received > left:
                    _refuse(rules.only_left(left))
                prepared.append((item, received, damaged))

            delivery = Delivery.objects.create(
                purchase_order=locked,
                received_by=user,
                received_at=timezone.now(),
            )
            DeliveryItem.objects.bulk_create([
                DeliveryItem(
                    delivery=delivery,
                    purchase_order_item=item,
                    qty_received=received,
                    qty_damaged=damaged,
                )
                for item, received, damaged in prepared
                if received > 0
            ])
            if receipt is not None:
                file_obj, display_name, extension = receipt
                delivery.receipt_file.save(display_name, file_obj, save=False)
                delivery.receipt_file_name = display_name
                delivery.receipt_content_type = uploads.content_type(extension)
                delivery.save(update_fields=[
                    'receipt_file', 'receipt_file_name', 'receipt_content_type',
                ])
                attached = True

            complete = all(
                _received_totals(locked).get(item.pk, ZERO) >= item.quantity
                for item in items.values()
            )
            locked.status = (
                PurchaseOrderStatus.DELIVERED if complete
                else PurchaseOrderStatus.PARTIALLY_DELIVERED
            )
            locked.save(update_fields=['status', 'updated_at'])

            damaged = any(row.qty_damaged > 0 for row in delivery.items.all())
            message = (
                f'Delivery received for {locked.po_no}'
                f'{" with damaged items" if damaged else ""}.'
            )
            record(
                user, 'delivery_confirmed', 'purchase_order', locked.pk,
                {'delivery_id': delivery.pk},
            )
            notify_project_role(
                locked.project, RoleOnProject.OWNER, message,
                type='delivery', link=f'{ORDERS_LINK}/{locked.pk}',
            )
            for accountant in User.objects.filter(
                is_active=True, user_roles__role=Role.ACCOUNTANT,
            ).distinct():
                notify(
                    accountant, 'delivery', message,
                    link=f'{ORDERS_LINK}/{locked.pk}',
                )
    except Exception:
        if attached and delivery is not None and delivery.receipt_file:
            delivery.receipt_file.delete(save=False)
        raise
    return delivery


def _received_totals(order):
    """PO line id -> quantity received so far (damaged included: it arrived)."""
    totals = {}
    for row in DeliveryItem.objects.filter(
        delivery__purchase_order=order,
    ).values('purchase_order_item_id', 'qty_received'):
        key = row['purchase_order_item_id']
        totals[key] = totals.get(key, ZERO) + row['qty_received']
    return totals


def budget_check(user, role, category, raw_amount):
    """`GET categories/{id}/procurement-budget/?amount=` — advisory, no writes."""
    if role not in capabilities.FINANCE_ROLES:
        raise NotAllowed(rules.NOT_FINANCE_BUDGET)
    if raw_amount in (None, ''):
        _refuse(rules.AMOUNT_REQUIRED)
    amount = rules.as_money(raw_amount)
    if amount is None:
        _refuse(rules.AMOUNT_INVALID)

    budget = category.budget
    # Every amount on this advisory wire is a 2-place decimal string.
    return {
        'budget': str(budget.quantize(ZERO)) if budget is not None and budget > 0 else None,
        'committed': str(committed_amount(category).quantize(ZERO)),
        'request_cost': str(amount.quantize(ZERO)),
    }
