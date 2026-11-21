"""Live reads from the store: its catalogue (price, stock status) and the debt it holds.

The store owns the price of what it sells and the record of what a project owes it, so
CPMS never keeps its own copy: each request asks the store through the CPMS service
account (`PosClient`). Nothing is written here and nothing is cached, so a screen always
shows the store's current answer, or says plainly that the store could not be reached.

Failures never leak internals (hosts, ports, the store's own text): the caller gets a
generic message and the detail stays in the CPMS log and `PosSyncLog`.
"""

import uuid
from decimal import ROUND_HALF_UP, Decimal

from django.db.models import DecimalField, ExpressionWrapper, F, Sum
from django.utils import timezone
from rest_framework import status as http_status
from rest_framework.decorators import api_view
from rest_framework.response import Response

from ..master_data.models import MaterialItem
from ..projects import scoping
from ..projects.rules import NotAllowed, RuleRefused
from ..users import capabilities
from ..users.models import Role
from .models import DeliveryItem, MaterialSource, PosRequestSnapshot, PurchaseOrder
from .pos_client import (
    PosConfigError,
    PosError,
    PosNotFound,
    PosRefused,
    _decimal,
    get_pos_client,
)

OWNER_ONLY = 'Only the project manager reads the store catalogue.'
FINANCE_ONLY = 'Owner or Accountant role required to see what a project owes the store.'
STORE_UNREACHABLE = 'The store could not be reached. Try again in a moment.'
STORE_NOT_CONFIGURED = 'The store connection is not set up on this server.'
STORE_UNREADABLE = 'The store sent an answer CPMS could not read.'
STOCK_STATUSES = {'in_stock', 'low', 'out'}


def _store_down(problem):
    if isinstance(problem, PosConfigError):
        return Response(
            {'detail': STORE_NOT_CONFIGURED},
            status=http_status.HTTP_503_SERVICE_UNAVAILABLE,
        )
    return Response(
        {'detail': STORE_UNREACHABLE}, status=http_status.HTTP_502_BAD_GATEWAY,
    )


@api_view(['GET'])
def pos_catalog_view(request):
    """`pos-catalog/` — the store's selling units with its price and stock status.

    Each row is joined to the CPMS material that carries the same `pos_code`, so an
    order line can use the server's own material id. A store item no CPMS material
    points at has `material_id: null` and cannot be ordered until an admin maps it.
    """
    if capabilities.active_role(request) != Role.OWNER:
        raise NotAllowed(OWNER_ONLY)
    try:
        rows = get_pos_client().list_materials()
    except PosError as problem:
        return _store_down(problem)

    rows = [row for row in rows if isinstance(row, dict) and row.get('code')]
    ids = {}
    for code, pk in MaterialItem.objects.filter(
        pos_code__in=[str(row['code']) for row in rows],
    ).order_by('-pk').values_list('pos_code', 'pk'):
        ids[code] = pk  # ascending pk wins when two materials share a code
    result = []
    for row in rows:
        price = _decimal(row.get('price'))
        stock = row.get('stock_status')
        result.append({
            'code': str(row['code']),
            'product': str(row.get('product') or ''),
            'unit': str(row.get('unit') or ''),
            # Unknown is null, never zero: a price we cannot read must not look free.
            'price': None if price is None else str(price),
            'stock_status': stock if stock in STOCK_STATUSES else None,
            'material_id': ids.get(str(row['code'])),
        })
    return Response(result)


CENT = Decimal('0.01')


def _store_cost_by_category(project, store_total: Decimal) -> dict[str, str]:
    """Attribute `store_total` across own-store PO categories for `project`.

    Uses undamaged delivered value on own-store POs first, falling back to POS
    snapshot released quantities × PO unit price (or PO line totals when
    released snapshots are not yet pulled), capped/scaled so category attributions
    never exceed `store_total`.
    """
    if store_total <= Decimal('0.00'):
        return {}

    raw_by_cat: dict[int, Decimal] = {}
    value_expr = ExpressionWrapper(
        (F('qty_received') - F('qty_damaged')) * F('purchase_order_item__unit_price'),
        output_field=DecimalField(max_digits=24, decimal_places=4),
    )
    delivered_rows = (
        DeliveryItem.objects.filter(
            delivery__purchase_order__project=project,
            delivery__purchase_order__source=MaterialSource.OWN_STORE,
            delivery__purchase_order__category__isnull=False,
        )
        .values('delivery__purchase_order__category')
        .annotate(total=Sum(value_expr))
        .order_by()
    )
    for row in delivered_rows:
        cat_id = row['delivery__purchase_order__category']
        amt = (row['total'] or Decimal('0.00')).quantize(CENT, rounding=ROUND_HALF_UP)
        if amt > Decimal('0.00'):
            raw_by_cat[cat_id] = raw_by_cat.get(cat_id, Decimal('0.00')) + amt

    if not raw_by_cat:
        orders = (
            PurchaseOrder.objects.filter(
                project=project,
                source=MaterialSource.OWN_STORE,
                category__isnull=False,
            )
            .prefetch_related('items__material')
            .select_related('pos_snapshot')
        )
        for order in orders:
            cat_id = order.category_id
            if not cat_id:
                continue
            snap = getattr(order, 'pos_snapshot', None)
            order_val = Decimal('0.00')
            if snap is not None and isinstance(snap.lines, list) and snap.lines:
                price_by_code = {
                    item.material.pos_code: item.unit_price
                    for item in order.items.all()
                    if item.material_id and item.material and item.material.pos_code
                }
                for line in snap.lines:
                    if not isinstance(line, dict):
                        continue
                    released = _decimal(line.get('released')) or Decimal('0.00')
                    unit_price = price_by_code.get(str(line.get('code') or ''))
                    if released > Decimal('0.00') and unit_price is not None:
                        order_val += (released * unit_price).quantize(
                            CENT, rounding=ROUND_HALF_UP
                        )
            if order_val > Decimal('0.00'):
                raw_by_cat[cat_id] = raw_by_cat.get(cat_id, Decimal('0.00')) + order_val

    raw_sum = sum(raw_by_cat.values(), Decimal('0.00'))
    if raw_sum <= Decimal('0.00'):
        return {}
    if raw_sum <= store_total:
        return {str(k): str(v.quantize(CENT, rounding=ROUND_HALF_UP)) for k, v in raw_by_cat.items()}

    # Scale down proportionally so attributed categories never exceed store_total.
    scaled: dict[str, str] = {}
    remaining = store_total
    items = list(raw_by_cat.items())
    for idx, (cat_id, val) in enumerate(items):
        if idx == len(items) - 1:
            share = max(Decimal('0.00'), remaining)
        else:
            share = (store_total * val / raw_sum).quantize(CENT, rounding=ROUND_HALF_UP)
            remaining -= share
        if share > Decimal('0.00'):
            scaled[str(cat_id)] = str(share)
    return scaled


@api_view(['GET'])
def pos_payables_view(request, pk):
    """`projects/{id}/pos-payables/` — what this project owes the store, as the store says.

    The store holds the debt record (owner decision 2026-11-15); CPMS only reads it.
    The store knows the project by its CPMS `code`. A project the store has never been
    sent reads as nothing owed yet (`at_store: false`); an unreadable answer is a 502,
    never a fabricated zero.
    """
    role = capabilities.active_role(request)
    if role not in capabilities.FINANCE_ROLES:
        raise NotAllowed(FINANCE_ONLY)
    project = scoping.project_or_404(request.user, role, pk)
    try:
        body = get_pos_client().project_payables(project.code)
    except PosNotFound:
        return Response({
            'project_id': project.pk, 'at_store': False,
            'total': '0.00', 'paid': '0.00', 'balance': '0.00',
            'by_category': {},
            'fetched_at': timezone.now().isoformat(),
        })
    except PosError as problem:
        return _store_down(problem)

    amounts = {
        key: _decimal(body.get(key)) if isinstance(body, dict) else None
        for key in ('total', 'paid', 'balance')
    }
    if any(value is None for value in amounts.values()):
        return Response(
            {'detail': STORE_UNREADABLE}, status=http_status.HTTP_502_BAD_GATEWAY,
        )
    store_total = amounts['total'] or Decimal('0.00')
    return Response({
        'project_id': project.pk, 'at_store': True,
        **{key: str(value) for key, value in amounts.items()},
        'by_category': _store_cost_by_category(project, store_total),
        'fetched_at': timezone.now().isoformat(),
    })


@api_view(['GET', 'POST'])
def pos_payment_receipts_view(request, pk):
    """`projects/{id}/pos-payment-receipts/` — list or submit online payment proofs to the store."""
    role = capabilities.active_role(request)
    if role not in capabilities.FINANCE_ROLES:
        raise NotAllowed(FINANCE_ONLY)
    project = scoping.project_or_404(request.user, role, pk)

    if request.method == 'GET':
        try:
            rows = get_pos_client().list_payment_receipts(project.code)
        except PosNotFound:
            return Response([])
        except PosError as problem:
            return _store_down(problem)
        return Response(rows if isinstance(rows, list) else [])

    if not capabilities.manages_finance(role):
        raise NotAllowed(FINANCE_ONLY)

    data = request.data if isinstance(request.data, dict) else {}
    amount = _decimal(data.get('amount'))
    if amount is None or amount <= Decimal('0.00'):
        raise RuleRefused('Enter a payment amount greater than zero.')
    reference_no = str(data.get('reference_no') or '').strip()
    if not reference_no:
        raise RuleRefused('Enter the payment reference number.')
    payment_method = str(data.get('payment_method') or 'BANK_TRANSFER').strip().upper()
    notes = str(data.get('notes') or '').strip()
    cpms_payment_id = str(data.get('cpms_payment_id') or uuid.uuid4()).strip()
    submitted_by = getattr(request.user, 'full_name', '') or str(request.user)

    try:
        receipt = get_pos_client().submit_payment_receipt(
            project.code,
            {
                'cpms_payment_id': cpms_payment_id,
                'amount': str(amount),
                'payment_method': payment_method,
                'reference_no': reference_no,
                'notes': notes,
                'submitted_by_name': submitted_by,
            },
        )
    except PosNotFound as err:
        raise RuleRefused(
            'This project has no store ledger yet. Release an order at the store first.'
        ) from err
    except PosRefused as err:
        raise RuleRefused(err.detail or 'The store refused the payment receipt.') from err
    except PosError as problem:
        return _store_down(problem)

    return Response(receipt, status=http_status.HTTP_201_CREATED)
