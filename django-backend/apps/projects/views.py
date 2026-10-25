"""Projects app views."""

from rest_framework import viewsets
from rest_framework.filters import OrderingFilter, SearchFilter

from ..users.permissions import IsAdminOrReadOnly
from .models import Contract, Milestone, Project, ProjectPhase, Site
from .serializers import (
    ContractSerializer,
    MilestoneSerializer,
    ProjectDetailSerializer,
    ProjectPhaseSerializer,
    ProjectSerializer,
    SiteSerializer,
)


class SiteViewSet(viewsets.ModelViewSet):
    queryset = Site.objects.all()
    serializer_class = SiteSerializer
    permission_classes = [IsAdminOrReadOnly]
    filter_backends = [SearchFilter, OrderingFilter]
    search_fields = ['code', 'name', 'city', 'province']
    ordering_fields = ['code', 'name', 'status', 'created_at']
    ordering = ['code']

    def get_queryset(self):
        queryset = super().get_queryset()
        status_param = self.request.query_params.get('status')
        if status_param:
            queryset = queryset.filter(status=status_param)
        return queryset


class ProjectViewSet(viewsets.ModelViewSet):
    queryset = Project.objects.select_related('site', 'manager').all()
    permission_classes = [IsAdminOrReadOnly]
    filter_backends = [SearchFilter, OrderingFilter]
    search_fields = ['code', 'name', 'site__name', 'site__code']
    ordering_fields = ['code', 'name', 'status', 'start_date', 'budget_amount']
    ordering = ['code']

    def get_serializer_class(self):
        if self.action == 'retrieve':
            return ProjectDetailSerializer
        return ProjectSerializer

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        status_param = params.get('status')
        if status_param:
            queryset = queryset.filter(status=status_param)

        site_param = params.get('site')
        if site_param:
            queryset = queryset.filter(site_id=site_param)

        manager_param = params.get('manager')
        if manager_param:
            queryset = queryset.filter(manager_id=manager_param)

        return queryset


class ContractViewSet(viewsets.ModelViewSet):
    queryset = Contract.objects.select_related('project').all()
    serializer_class = ContractSerializer
    permission_classes = [IsAdminOrReadOnly]
    filter_backends = [SearchFilter, OrderingFilter]
    search_fields = ['contract_no', 'client_name', 'project__code']
    ordering_fields = ['contract_no', 'amount', 'signed_date', 'status']
    ordering = ['-signed_date']

    def get_queryset(self):
        queryset = super().get_queryset()
        project_param = self.request.query_params.get('project')
        if project_param:
            queryset = queryset.filter(project_id=project_param)
        return queryset


class ProjectPhaseViewSet(viewsets.ModelViewSet):
    queryset = ProjectPhase.objects.select_related('project').all()
    serializer_class = ProjectPhaseSerializer
    permission_classes = [IsAdminOrReadOnly]


class MilestoneViewSet(viewsets.ModelViewSet):
    queryset = Milestone.objects.select_related('project', 'phase').all()
    serializer_class = MilestoneSerializer
    permission_classes = [IsAdminOrReadOnly]
    filter_backends = [OrderingFilter]
    ordering_fields = ['due_date', 'title']
    ordering = ['due_date']