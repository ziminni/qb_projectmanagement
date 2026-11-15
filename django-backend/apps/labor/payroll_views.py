"""Payroll views: periods, verification, advances, processing, labor cost.

Check order follows the Phase 2/3/4 convention:

1. authentication (global DRF default);
2. **scope** via `scoping.project_or_404()` / `projects_for()` — out of scope
   is always `404`;
3. the **active role** — `capabilities.active_role()`, never a union of held
   roles; the wrong active role is `403`;
4. the business rule, which answers `400 {"detail": "<text>"}`.

Who may do what:

* any staff role reads period rows (a site engineer needs the cut-off calendar
  to know which days are locked); the client portal is refused everything;
* the **accountant** creates periods, moves cash advances and processes pay;
* the accepted **owner** of the project verifies attendance;
* wages — `lines/` and `labor-cost/` — are visible to the finance roles
  (owner, accountant) only.
"""

# Pyright runs without django-stubs/DRF stubs (untyped managers, actions).
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportGeneralTypeIssues=false

from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from ..projects import scoping
from ..projects.rules import NotAllowed, RuleRefused
from ..users import capabilities
from ..users.models import Role
from . import payroll_rules as payroll
from . import payroll_serializers as wire
from . import payroll_services
from . import rules as labor
from .models import PayrollPeriod
from .views import first_error, require_staff


def require_accountant(role):
    """Period money moves for the accountant role only (the UI's `canCreate`)."""
    if role != Role.ACCOUNTANT:
        raise NotAllowed(payroll.ACCOUNTANT_ONLY)


def require_finance(role):
    """Owner or accountant: wages never reach a site engineer or an admin."""
    if not capabilities.sees_finance(role):
        raise NotAllowed(payroll.FINANCE_ONLY)


def refused(serializer):
    return Response({'detail': first_error(serializer.errors)},
                    status=status.HTTP_400_BAD_REQUEST)


def query_project_id(request):
    """The `?project=` value as an int; missing and junk are `400`."""
    raw = request.query_params.get('project')
    if not raw:
        raise RuleRefused(labor.PROJECT_REQUIRED)
    if isinstance(raw, bool):
        raise RuleRefused(labor.PROJECT_NOT_FOUND)
    try:
        return int(str(raw).strip())
    except (TypeError, ValueError) as error:
        raise RuleRefused(labor.PROJECT_NOT_FOUND) from error


class PayrollPeriodViewSet(viewsets.GenericViewSet,
                           mixins.ListModelMixin,
                           mixins.RetrieveModelMixin):
    """`payroll-periods/` — the cut-off calendar plus the payroll moves."""

    serializer_class = wire.PayrollPeriodSerializer
    http_method_names = ('get', 'post', 'head', 'options')

    def role(self):
        return capabilities.active_role(self.request)

    def get_queryset(self):
        role = self.role()
        require_staff(role)
        return PayrollPeriod.objects.select_related('project').filter(
            project__in=scoping.projects_for(self.request.user, role),
        )

    def list(self, request, *args, **kwargs):
        queryset = self.get_queryset()
        raw_project = request.query_params.get('project')
        if raw_project:
            queryset = queryset.filter(project_id=query_project_id(request))
        page = self.paginate_queryset(queryset)
        serializer = self.get_serializer(page, many=True)
        return self.get_paginated_response(serializer.data)

    def create(self, request, *args, **kwargs):
        role = self.role()
        require_accountant(role)
        serializer = wire.CreatePeriodSerializer(data=request.data)
        if not serializer.is_valid():
            return refused(serializer)
        data = serializer.validated_data
        project = scoping.project_or_404(
            request.user, role, data['project_id'],
        )
        period = payroll_services.create_period(
            request.user, project, data['period_start'], data['period_end'],
        )
        return Response(self.get_serializer(period).data,
                        status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'])
    def verify(self, request, pk=None):
        role = self.role()
        period = self.get_object()
        if role != Role.OWNER:
            raise NotAllowed(payroll.OWNER_VERIFIES)
        period = payroll_services.verify_period(request.user, period)
        return Response(self.get_serializer(period).data)

    @action(detail=True, methods=['post'], url_path='cash-advance')
    def cash_advance(self, request, pk=None):
        role = self.role()
        period = self.get_object()
        require_accountant(role)
        serializer = wire.CashAdvanceSerializer(data=request.data)
        if not serializer.is_valid():
            return refused(serializer)
        line = payroll_services.set_cash_advance(
            request.user, period,
            serializer.validated_data['worker_id'],
            serializer.validated_data['amount'],
        )
        return Response(wire.PayrollLineSerializer(line).data)

    @action(detail=True, methods=['get'])
    def lines(self, request, pk=None):
        role = self.role()
        period = self.get_object()
        require_finance(role)
        rows = payroll_services.lines_for(period)
        return Response(wire.PayrollLineSerializer(rows, many=True).data)

    @action(detail=True, methods=['post'])
    def process(self, request, pk=None):
        role = self.role()
        period = self.get_object()
        require_accountant(role)
        period = payroll_services.process_period(request.user, period)
        return Response(self.get_serializer(period).data)


class LaborCostView(APIView):
    """`labor-cost/?project=ID` — gross pay of the project's processed periods."""

    def get(self, request):
        role = capabilities.active_role(request)
        require_finance(role)
        project = scoping.project_or_404(
            request.user, role, query_project_id(request),
        )
        return Response({
            'project_id': project.pk,
            'labor_cost': f'{payroll_services.labor_cost(project):.2f}',
        })
