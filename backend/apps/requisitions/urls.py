"""Requisitions app URL configuration."""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    MaterialRequestItemViewSet,
    MaterialRequestViewSet,
    PosSyncLogViewSet,
    ReleaseTokenViewSet,
)

router = DefaultRouter()
router.register(r'requisitions', MaterialRequestViewSet, basename='requisition')
router.register(r'requisition-items', MaterialRequestItemViewSet, basename='requisitionitem')
router.register(r'release-tokens', ReleaseTokenViewSet, basename='releasetoken')
router.register(r'pos-sync-logs', PosSyncLogViewSet, basename='possynclog')

urlpatterns = [
    path('', include(router.urls)),
]