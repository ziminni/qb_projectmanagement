"""Site inventory app views."""

from django.db.models import F
from rest_framework import viewsets

from ..users.permissions import IsAdminOrReadOnly
from .models import Equipment, EquipmentLog, SiteStock, Tool
from .serializers import (
    EquipmentLogSerializer,
    EquipmentSerializer,
    SiteStockSerializer,
    ToolSerializer,
)


class SiteStockViewSet(viewsets.ModelViewSet):
    """Site stock on hand, filterable per site and by reorder status."""

    queryset = SiteStock.objects.select_related('site').all()
    serializer_class = SiteStockSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        site = params.get('site')
        if site:
            queryset = queryset.filter(site_id=site)

        search = params.get('search')
        if search:
            queryset = queryset.filter(item_name__icontains=search)

        if params.get('below_reorder_level', '').lower() in ('1', 'true', 'yes'):
            queryset = queryset.filter(quantity_on_hand__lte=F('reorder_level'))

        return queryset


class ToolViewSet(viewsets.ModelViewSet):
    queryset = Tool.objects.select_related('site', 'custodian').all()
    serializer_class = ToolSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        site = params.get('site')
        if site:
            queryset = queryset.filter(site_id=site)

        condition = params.get('condition')
        if condition:
            queryset = queryset.filter(condition=condition)

        return queryset


class EquipmentViewSet(viewsets.ModelViewSet):
    queryset = Equipment.objects.select_related('site', 'operator').all()
    serializer_class = EquipmentSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        site = params.get('site')
        if site:
            queryset = queryset.filter(site_id=site)

        status_param = params.get('status')
        if status_param:
            queryset = queryset.filter(status=status_param)

        return queryset


class EquipmentLogViewSet(viewsets.ModelViewSet):
    """Movement / status history for equipment."""

    queryset = EquipmentLog.objects.select_related('equipment', 'site', 'logged_by').all()
    serializer_class = EquipmentLogSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        equipment = self.request.query_params.get('equipment')
        if equipment:
            queryset = queryset.filter(equipment_id=equipment)
        return queryset

    def perform_create(self, serializer):
        """Stamp the reporting user as the logger by default."""
        if not serializer.validated_data.get('logged_by'):
            serializer.save(logged_by=self.request.user)
        else:
            serializer.save()