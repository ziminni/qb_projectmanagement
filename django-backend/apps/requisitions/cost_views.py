"""Outside-store materials cost, the CPMS half of a project's materials cost.

Owner decision 2026-11-15: own-store materials cost is what the store charged, read
from the store (`pos-payables/`), so it is never computed here. This route counts only
**external** purchases: undamaged received quantity × the order line's unit price,
summed per category in one query.
"""

from decimal import Decimal

from django.db.models import DecimalField, ExpressionWrapper, F, Sum
from rest_framework.decorators import api_view
from rest_framework.response import Response

from ..projects import scoping
from ..projects.rules import NotAllowed
from ..users import capabilities
from .models import DeliveryItem, MaterialSource

FINANCE_ONLY = 'Owner or Accountant role required to see project costs.'
CENT = Decimal('0.01')


@api_view(['GET'])
def external_materials_cost_view(request, pk):
    """`projects/{id}/external-materials-cost/` — `{project_id, by_category: {id: "0.00"}}`."""
    role = capabilities.active_role(request)
    if role not in capabilities.FINANCE_ROLES:
        raise NotAllowed(FINANCE_ONLY)
    project = scoping.project_or_404(request.user, role, pk)
    value = ExpressionWrapper(
        (F('qty_received') - F('qty_damaged')) * F('purchase_order_item__unit_price'),
        output_field=DecimalField(max_digits=24, decimal_places=4),
    )
    rows = (
        DeliveryItem.objects
        .filter(
            delivery__purchase_order__project=project,
            delivery__purchase_order__source=MaterialSource.EXTERNAL,
            delivery__purchase_order__category__isnull=False,
        )
        .values('delivery__purchase_order__category')
        .annotate(total=Sum(value))
        .order_by()
    )
    return Response({
        'project_id': project.pk,
        'by_category': {
            str(row['delivery__purchase_order__category']): str(row['total'].quantize(CENT))
            for row in rows
        },
    })
