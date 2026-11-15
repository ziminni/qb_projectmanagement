"""Derived site inventory and committed amounts — **reads only, zero writes**.

Site inventory is never stored (decision 05, `services/inventory_calculator.dart`):

    on hand = delivered (received) − damaged − approved daily-report usage

A negative figure is kept, never clamped, and a site count never overwrites it:
a variance between the count and the system figure is evidence for the owner.
Damaged goods never enter inventory (or delivered-good costing).

The key mirrors the mock: `m{material_id}` for price-list material, else
`n:{trimmed lower-case name}`.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false

from decimal import Decimal

from django.db.models import Sum

from ..site_reports.models import DailyReportStatus, ReportMaterialUsage
from .models import DeliveryItem, PurchaseOrder, PurchaseOrderItem, PurchaseOrderStatus

ZERO = Decimal('0.00')


def inventory_key(material_id, name):
    """`m7` for a price-list material, else `n:portland cement`."""
    if material_id:
        return f'm{int(material_id)}'
    return f'n:{str(name or "").strip().lower()}'


def _line(store, key, material_id, name, unit):
    """One inventory line, created once per key (first resolution wins)."""
    if key not in store:
        store[key] = {
            'material_id': int(material_id) if material_id else None,
            'name': str(name or '').strip(),
            'unit': str(unit or '').strip(),
            'received': ZERO,
            'damaged': ZERO,
            'used': ZERO,
        }
    return store[key]


def site_inventory(project):
    """`[InventoryLine]` for one project: received, damaged, used (no money)."""
    items = PurchaseOrderItem.objects.filter(
        purchase_order__project=project,
    ).select_related('material')
    item_by_id = {item.pk: item for item in items}

    store = {}
    for row in DeliveryItem.objects.filter(
        purchase_order_item__purchase_order__project=project,
    ).select_related('purchase_order_item__material'):
        item = item_by_id.get(row.purchase_order_item_id)
        if item is None:  # pragma: no cover - FK makes this unreachable
            continue
        key = inventory_key(
            item.material_id, item.material.name if item.material else item.description,
        )
        line = _line(
            store,
            key,
            item.material_id,
            item.material.name if item.material else item.description,
            item.material.unit if item.material else item.unit,
        )
        line['received'] += row.qty_received
        line['damaged'] += row.qty_damaged

    for usage in ReportMaterialUsage.objects.filter(
        daily_report__project=project,
        daily_report__status=DailyReportStatus.APPROVED,
    ).select_related('material'):
        key = inventory_key(
            usage.material_id, usage.material.name if usage.material else usage.material_id,
        )
        line = _line(
            store,
            key,
            usage.material_id,
            usage.material.name if usage.material else f'Material #{usage.material_id}',
            usage.material.unit if usage.material else '',
        )
        line['used'] += usage.quantity

    lines = sorted(store.values(), key=lambda row: (row['name'].lower(), row['name']))
    for line in lines:
        line['on_hand'] = line['received'] - line['damaged'] - line['used']
    return lines


def committed_amount(category):
    """Material already ordered or bought for a category (cancelled excluded)."""
    total = PurchaseOrder.objects.filter(
        category=category,
    ).exclude(
        status=PurchaseOrderStatus.CANCELLED,
    ).aggregate(total=Sum('total_amount'))
    return total['total'] or ZERO
