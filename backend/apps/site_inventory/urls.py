"""Site inventory app URL configuration."""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    EquipmentLogViewSet,
    EquipmentViewSet,
    SiteStockViewSet,
    ToolViewSet,
)

router = DefaultRouter()
router.register(r'site-stock', SiteStockViewSet, basename='sitestock')
router.register(r'tools', ToolViewSet, basename='tool')
router.register(r'equipment', EquipmentViewSet, basename='equipment')
router.register(r'equipment-logs', EquipmentLogViewSet, basename='equipmentlog')

urlpatterns = [
    path('', include(router.urls)),
]