"""Master data app URL configuration (mounted under /api/v1/master-data/).

Routed under `master-data/` so `master-data/equipment/` cannot collide with the
legacy `equipment/` route in `apps/site_inventory/urls.py`.
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    EquipmentItemViewSet,
    MaterialItemViewSet,
    SupplierViewSet,
    TradeViewSet,
)

router = DefaultRouter()
router.register(r'materials', MaterialItemViewSet, basename='material')
router.register(r'suppliers', SupplierViewSet, basename='supplier')
router.register(r'trades', TradeViewSet, basename='trade')
router.register(r'equipment', EquipmentItemViewSet, basename='equipmentitem')

urlpatterns = [
    path('master-data/', include(router.urls)),
]
