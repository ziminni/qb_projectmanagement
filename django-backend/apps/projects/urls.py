"""Projects app URL configuration."""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    ContractViewSet,
    MilestoneViewSet,
    ProjectPhaseViewSet,
    ProjectViewSet,
    SiteViewSet,
)

router = DefaultRouter()
router.register(r'sites', SiteViewSet, basename='site')
router.register(r'projects', ProjectViewSet, basename='project')
router.register(r'contracts', ContractViewSet, basename='contract')
router.register(r'project-phases', ProjectPhaseViewSet, basename='projectphase')
router.register(r'milestones', MilestoneViewSet, basename='milestone')

urlpatterns = [
    path('', include(router.urls)),
]