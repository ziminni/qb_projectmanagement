"""Labor views: the company-wide worker picker and project attendance.

Check order follows the Phase 2/3 convention:

1. authentication (global DRF default);
2. **scope** via `scoping.project_or_404()` — out of scope is always `404`;
3. **active role** — in scope but the wrong active role is `403`;
4. the business rule, which answers `400 {"detail": "<text>"}`.

The active role is always `capabilities.active_role(request)`: held roles are
never unioned. Workers are company-wide; attendance is always project-scoped and
has no generic write route (only `save-day/`).
"""

# Pyright runs without django-stubs/DRF stubs (untyped managers, actions).
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportGeneralTypeIssues=false

from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from ..projects import scoping
from ..projects.models import RoleOnProject
from ..projects.rules import NotAllowed, RuleRefused
from ..users import capabilities
from ..users.models import Role
from . import rules, services
from .models import Attendance, Worker
from .serializers import (
    AttendanceSerializer,
    SaveDaySerializer,
    WorkerSerializer,
    parse_iso_date,
)


def first_error(errors):
    """The first DRF error text, through nested list/entry dicts.

    Unlike `master_data.serializers.refusal`, this walks a `many=True` entry
    error so a bad overtime in the second row still becomes one clean string.
    """
    for value in errors.values():
        if isinstance(value, dict):
            return first_error(value)
        if isinstance(value, list) and value:
            first = value[0]
            if isinstance(first, dict):
                return first_error(first)
            return str(first)
        return str(value)
    return 'This change was refused.'


def require_staff(role):
    """The client portal has no labor surface (it sees neither names nor wages)."""
    if role not in capabilities.STAFF_ROLES:
        raise NotAllowed(rules.STAFF_ONLY)


def query_bool(raw, name):
    """A query-string boolean is `true`/`false` only; anything else is a `400`."""
    value = str(raw).strip().lower()
    if value not in ('true', 'false'):
        raise RuleRefused(f'The {name} filter must be true or false.')
    return value == 'true'


def filter_date(request, name):
    """`?from=2026-11-01` as a date; a junk value is a `400`."""
    raw = request.query_params.get(name)
    if not raw:
        return None
    try:
        return parse_iso_date(raw)
    except ValueError as error:
        raise RuleRefused(rules.FILTER_DATE.format(name=name)) from error


def project_id_from(request):
    """The `project_id` body value as an int; junk/booleans are a `400`."""
    raw = request.data.get('project_id')
    if isinstance(raw, bool) or raw is None:
        raise RuleRefused(rules.PROJECT_NOT_FOUND)
    if isinstance(raw, int):
        return raw
    try:
        return int(str(raw).strip())
    except (TypeError, ValueError) as error:
        raise RuleRefused(rules.PROJECT_NOT_FOUND) from error


class WorkerViewSet(viewsets.GenericViewSet,
                    mixins.ListModelMixin,
                    mixins.RetrieveModelMixin):
    """`workers/` — staff picker plus owner/accountant maintenance."""

    serializer_class = WorkerSerializer
    # No PUT and no DELETE: workers are deactivated, never removed.
    http_method_names = ('get', 'post', 'patch', 'head', 'options')

    def role(self):
        return capabilities.active_role(self.request)

    def get_queryset(self):
        queryset = Worker.objects.select_related('trade')
        if self.action == 'list':
            raw = self.request.query_params.get('active_only')
            if raw is not None and raw != '':
                queryset = queryset.filter(is_active=query_bool(raw, 'active_only'))
        return queryset

    def list(self, request, *args, **kwargs):
        require_staff(self.role())
        return super().list(request, *args, **kwargs)

    def retrieve(self, request, *args, **kwargs):
        require_staff(self.role())
        return super().retrieve(request, *args, **kwargs)

    def require_maintenance(self):
        """Only the finance roles maintain workers company-wide."""
        if not capabilities.sees_finance(self.role()):
            raise NotAllowed(rules.WORKER_MAINTENANCE)

    def refused(self, serializer):
        return Response({'detail': first_error(serializer.errors)},
                        status=status.HTTP_400_BAD_REQUEST)

    def create(self, request, *args, **kwargs):
        self.require_maintenance()
        serializer = self.get_serializer(data=request.data)
        if not serializer.is_valid():
            return self.refused(serializer)
        worker = services.create_worker(request.user, serializer)
        return Response(self.get_serializer(worker).data,
                        status=status.HTTP_201_CREATED)

    def partial_update(self, request, *args, **kwargs):
        self.require_maintenance()
        worker = self.get_object()
        serializer = self.get_serializer(worker, data=request.data, partial=True)
        if not serializer.is_valid():
            return self.refused(serializer)
        worker = services.update_worker(request.user, serializer)
        return Response(self.get_serializer(worker).data)


class AttendanceViewSet(viewsets.GenericViewSet):
    """`attendance/` — scoped reads and the atomic `save-day/` action."""

    serializer_class = AttendanceSerializer
    # Read-only generic surface; the only write is `save-day/`.
    http_method_names = ('get', 'post', 'head', 'options')

    def role(self):
        return capabilities.active_role(self.request)

    def list(self, request):
        role = self.role()
        require_staff(role)

        raw_project = request.query_params.get('project')
        if not raw_project:
            raise RuleRefused(rules.PROJECT_REQUIRED)
        try:
            project_id = int(raw_project)
        except (TypeError, ValueError) as error:
            raise RuleRefused(rules.PROJECT_NOT_FOUND) from error
        project = scoping.project_or_404(request.user, role, project_id)

        date_from = filter_date(request, 'from')
        date_to = filter_date(request, 'to')
        if date_from is not None and date_to is not None and date_from > date_to:
            raise RuleRefused(rules.REVERSED_DATES)

        queryset = Attendance.objects.filter(project=project)
        if date_from is not None:
            queryset = queryset.filter(work_date__gte=date_from)
        if date_to is not None:
            queryset = queryset.filter(work_date__lte=date_to)
        return Response(self.get_serializer(queryset, many=True).data)

    @action(detail=False, methods=['post'], url_path='save-day')
    def save_day(self, request):
        role = self.role()
        require_staff(role)

        # Scope before the business rule: an unrelated project is a `404`.
        project = scoping.project_or_404(
            request.user, role, project_id_from(request),
        )
        # Writing attendance needs the active site_engineer role AND an accepted
        # site_engineer assignment; holding the role elsewhere is not enough.
        if role != Role.SITE_ENGINEER or not scoping.has_accepted_assignment(
            project, request.user, RoleOnProject.SITE_ENGINEER,
        ):
            raise NotAllowed(rules.SE_ONLY)

        serializer = SaveDaySerializer(data=request.data)
        if not serializer.is_valid():
            raise RuleRefused(first_error(serializer.errors))

        rows = services.save_day(
            request.user, project,
            serializer.validated_data['work_date'],
            serializer.validated_data['entries'],
        )
        return Response(AttendanceSerializer(rows, many=True).data)
