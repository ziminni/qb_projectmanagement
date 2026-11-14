"""Requisitions / procurement URL configuration (routed under /api/v1/).

Phase 3 routes (contract `phase-3-procurement.md`):

* `material-requests/` (+ `{id}/reject/`) — list, detail, create, reject;
* `purchase-orders/` (+ `{id}/cancel/`, `{id}/deliveries/`) — place, list,
  detail, cancel, confirm a delivery;
* `deliveries/?project=` — newest first, each with its order;
* `projects/{id}/site-inventory/` — derived, zero writes;
* `categories/{id}/procurement-budget/?amount=` — advisory, finance roles only;
* `purchase-orders/{id}/receipt/{name}` and `deliveries/{id}/receipt/{name}` —
  private receipt evidence (finance roles only).

**Retired here on purpose** (history kept, routes gone): the legacy
`requisitions/`, `requisition-items/`, `release-tokens/` (including the
`redeem/` callback, a bearer secret any authenticated caller could redeem) and
`pos-sync-logs/` routes. They bypassed Phase 2 project scoping entirely; their
models and rows are untouched. The POS bridge that replaces them is task 3.1b.
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .procurement_views import (
    DeliveryViewSet,
    MaterialRequestViewSet,
    PurchaseOrderViewSet,
    category_budget_view,
    delivery_receipt_view,
    project_site_inventory_view,
    purchase_order_receipt_view,
)

router = DefaultRouter()
router.register(r'material-requests', MaterialRequestViewSet, basename='materialrequest')
router.register(r'purchase-orders', PurchaseOrderViewSet, basename='purchaseorder')
router.register(r'deliveries', DeliveryViewSet, basename='delivery')

urlpatterns = [
    path(
        'projects/<int:pk>/site-inventory/', project_site_inventory_view,
        name='project-site-inventory',
    ),
    path(
        'categories/<int:pk>/procurement-budget/', category_budget_view,
        name='category-procurement-budget',
    ),
    path(
        'purchase-orders/<int:pk>/receipt/<str:file_name>',
        purchase_order_receipt_view, name='purchase-order-receipt',
    ),
    path(
        'deliveries/<int:pk>/receipt/<str:file_name>',
        delivery_receipt_view, name='delivery-receipt',
    ),
    path('', include(router.urls)),
]
