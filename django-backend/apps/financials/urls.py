"""Financials app URL configuration."""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

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

urlpatterns = [
    path('', include(router.urls)),
]