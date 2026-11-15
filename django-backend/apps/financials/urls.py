"""Financials app URL configuration.

Two clusters live here:

* the legacy budget / expense / collectible routes (Kept as they were), and
* the Phase 4 slice 4.2a client-facing billing routes:
  `progress-billings/`, `client-payments/`, `billing-summary/`,
  `variation-orders/`, `retention/` and `retention-releases/`.

Derived project costs are not here: outside-store materials cost is
`requisitions` `projects/{id}/external-materials-cost/`, own-store materials are the
store's charge (`pos-payables/`), labor is `labor-cost/`. Supplier payables are absent.
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .billing_views import (
    BillingSummaryView,
    ClientPaymentViewSet,
    ProgressBillingViewSet,
    RetentionReleaseViewSet,
    RetentionView,
    VariationOrderViewSet,
)
from .views import (
    CollectiblePaymentViewSet,
    CollectibleViewSet,
    ExpenseLogViewSet,
    ProjectBudgetViewSet,
)

router = DefaultRouter()
router.register(r'budgets', ProjectBudgetViewSet, basename='budget')
router.register(r'expenses', ExpenseLogViewSet, basename='expense')
router.register(r'collectibles', CollectibleViewSet, basename='collectible')
router.register(r'collectible-payments', CollectiblePaymentViewSet, basename='collectiblepayment')

router.register(r'progress-billings', ProgressBillingViewSet, basename='progressbilling')
router.register(r'client-payments', ClientPaymentViewSet, basename='clientpayment')
router.register(r'variation-orders', VariationOrderViewSet, basename='variationorder')
router.register(r'retention-releases', RetentionReleaseViewSet, basename='retentionrelease')

urlpatterns = [
    path('', include(router.urls)),
    path('billing-summary/', BillingSummaryView.as_view(), name='billing-summary'),
    path('retention/', RetentionView.as_view(), name='retention'),
]
