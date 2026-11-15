"""Projects app views — scoped reads, role-checked writes (Phase 2 contract).

Order of every check mirrors the contract:

1. authentication (global DRF default);
2. **scope** via `scoping.projects_for()` — out of scope is always `404`;
3. **role** on the resolved object — in scope but wrong role is `403`;
4. the business rule, which answers `400 {"detail": "<mock text>"}`.

Writes live in `services.py`; this file only picks querysets and serializers.
"""

# Pyright here runs without django-stubs/DRF stubs (untyped managers, actions).
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportGeneralTypeIssues=false

from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view
from rest_framework.filters import OrderingFilter, SearchFilter
from rest_framework.response import Response

from ..users import capabilities
from ..users.models import Role, User
from ..users.permissions import IsAdminOrReadOnly
from . import scoping, services
from .models import (
    Category,
    Client,
    ProjectAssignment,
    ProjectStatus,
    RequestResponse,
    Site,
    Todo,
)
from .rules import CLIENT_WRITE, NotAllowed, RuleRefused
from .serializers import (
    CategorySerializer,
    ClientSerializer,
    ProjectAssignmentSerializer,
    ProjectRequestSerializer,
    ProjectSerializer,
    SiteSerializer,
    TodoSerializer,
    category_weights,
)

# Messages for the writes only an assigned owner may make (*proposed* texts).
SCHEDULE_WRITE = 'Only the owner running this project can change its schedule.'
VERIFY_ONLY = 'Only the owner running this project can verify to-dos.'
TICK_ONLY = 'Only the site engineer or owner assigned to this project can tick to-dos.'


def numeric_filter(request, name):
    """The numeric value of `?<name>=`, or a `400` — never a `ValueError` 500.

    A junk filter (review 2.1 minor 3: `project-assignments/?project=abc`) is a
    caller mistake, so it answers the same `{"detail": ...}` shape as the other
    refusals instead of reaching the ORM.
    """
    value = request.query_params.get(name)
    if not value:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        raise RuleRefused(f'The {name} filter must be a number.')


def as_bool(value):
    """Accept the JSON boolean Flutter sends (and the obvious string forms)."""
    return value in (True, 1, '1', 'true', 'True')


def category_payload(project, role, categories):
    """Render categories with the server-computed weight for this project."""
    return CategorySerializer(
        categories,
        many=True,
        context={'role': role, 'weights': category_weights(project)},
    ).data


class ScopedViewSet(viewsets.GenericViewSet):
    """Shared helpers: the active role and the scoped project queryset."""

    pagination_class = None

    def role(self):
        return capabilities.active_role(self.request)

    def projects(self):
        return scoping.projects_for(self.request.user, self.role())

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context['role'] = self.role()
        return context


class ProjectViewSet(ScopedViewSet):
    """`projects/` — list, detail, create, edit and the request workflow actions."""

    serializer_class = ProjectSerializer

    def get_queryset(self):
        return self.projects().select_related('client')

    def list(self, request):
        return Response(
            self.get_serializer(self.get_queryset(), many=True).data
        )

    def retrieve(self, request, pk=None):
        return Response(self.get_serializer(self.get_object()).data)

    def create(self, request):
        project = services.create_project(request.user, self.role(), request.data)
        return Response(
            self.get_serializer(project).data, status=status.HTTP_201_CREATED,
        )

    def partial_update(self, request, pk=None):
        project = services.update_project(
            request.user, self.role(), self.get_object(), request.data,
        )
        project.refresh_from_db()
        return Response(self.get_serializer(project).data)

    @action(detail=True, methods=['post'])
    def status(self, request, pk=None):
        """Owner-only manual status move (`projects/{id}/status/`)."""
        project = services.change_status(
            request.user, self.role(), self.get_object(), request.data.get('status'),
        )
        return Response(self.get_serializer(project).data)

    @action(detail=True, methods=['post'])
    def resend(self, request, pk=None):
        """Owner sends a change-requested project back to the client."""
        project = services.resend_request(
            request.user, self.role(), self.get_object(),
        )
        return Response(self.get_serializer(project).data)

    @action(detail=True, methods=['get', 'post'], url_path='assignments')
    def assignments(self, request, pk=None):
        """The project team (staff only), or the owner adding someone."""
        project = self.get_object()
        if request.method == 'GET':
            scoping.require_staff(
                self.role(), 'Only the project team can see who is on the project.',
            )
            return Response(
                ProjectAssignmentSerializer(
                    project.assignments.select_related('user'), many=True,
                ).data
            )
        assignment = services.assign(request.user, self.role(), project, request.data)
        return Response(
            ProjectAssignmentSerializer(assignment).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=['get', 'post'], url_path='categories')
    def categories(self, request, pk=None):
        project = self.get_object()
        if request.method == 'GET':
            return Response(
                category_payload(project, self.role(), project.categories.all())
            )
        scoping.require_owner(project, request.user, SCHEDULE_WRITE)
        category = services.save_category(project, request.data)
        return Response(
            category_payload(project, self.role(), [category])[0],
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=['get'])
    def todos(self, request, pk=None):
        project = self.get_object()
        rows = Todo.objects.filter(category__project=project).select_related('category')
        return Response(TodoSerializer(rows, many=True).data)


class ProjectAssignmentViewSet(ScopedViewSet):
    """`project-assignments/` — list a user's rows, remove one, answer a request."""

    serializer_class = ProjectAssignmentSerializer

    def get_queryset(self):
        queryset = ProjectAssignment.objects.select_related('project', 'user')
        if self.role() == Role.ADMIN:
            return queryset
        return queryset.filter(user=self.request.user)

    def list(self, request):
        role = self.role()
        user_param = request.query_params.get('user')
        if role != Role.ADMIN and user_param and str(request.user.pk) != str(user_param):
            raise NotAllowed('You can only see your own assignments.')
        queryset = self.get_queryset()
        user_id = numeric_filter(request, 'user')
        if user_id is not None:
            queryset = queryset.filter(user_id=user_id)
        project_id = numeric_filter(request, 'project')
        if project_id is not None:
            queryset = queryset.filter(project_id=project_id)
        for name in ('role_on_project', 'response'):
            value = request.query_params.get(name)
            if value:
                queryset = queryset.filter(**{name: value})
        return Response(ProjectAssignmentSerializer(queryset, many=True).data)

    def destroy(self, request, pk=None):
        assignment = get_object_or_404(ProjectAssignment.objects.select_related('project'), pk=pk)
        role = self.role()
        if role != Role.ADMIN:
            scoping.project_or_404(request.user, role, assignment.project_id)
            scoping.require_owner(
                assignment.project, request.user,
                'Only the owner running this project can remove people from it.',
            )
        services.unassign(request.user, assignment)
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=['post'])
    def respond(self, request, pk=None):
        """The assignee answers their own request (any other user gets `404`)."""
        assignment = get_object_or_404(
            ProjectAssignment.objects.select_related('project'), pk=pk,
        )
        assignment = services.respond(
            request.user, self.role(), assignment, request.data,
        )
        return Response(ProjectAssignmentSerializer(assignment).data)


class ProjectRequestViewSet(ScopedViewSet):
    """`project-requests/` — the caller's pending requests in the active role."""

    serializer_class = ProjectRequestSerializer

    def list(self, request):
        rows = (
            ProjectAssignment.objects
            .filter(
                user=request.user,
                role_on_project=self.role(),
                response=RequestResponse.PENDING,
            )
            .exclude(project__status=ProjectStatus.DECLINED)
            .select_related('project')
            .order_by('pk')
        )
        return Response(
            ProjectRequestSerializer(
                rows, many=True, context={'role': self.role()},
            ).data
        )


class CategoryViewSet(ScopedViewSet):
    """`categories/{id}/` — edit or delete one category."""

    serializer_class = CategorySerializer

    def get_queryset(self):
        return Category.objects.filter(
            project__in=self.projects(),
        ).select_related('project')

    def partial_update(self, request, pk=None):
        category = self.get_object()
        scoping.require_owner(category.project, request.user, SCHEDULE_WRITE)
        services.save_category(category.project, request.data, category=category)
        return Response(
            category_payload(category.project, self.role(), [category])[0]
        )

    def destroy(self, request, pk=None):
        category = self.get_object()
        scoping.require_owner(category.project, request.user, SCHEDULE_WRITE)
        services.delete_category(category)
        return Response(status=status.HTTP_204_NO_CONTENT)


class TodoViewSet(ScopedViewSet):
    """`todos/` — create, edit, delete, tick, verify and un-verify."""

    serializer_class = TodoSerializer

    def get_queryset(self):
        return Todo.objects.filter(
            category__project__in=self.projects(),
        ).select_related('category', 'category__project')

    def category_in_project(self, raw_category_id, project=None):
        """Resolve the body's `category_id` inside the caller's scope, else 404."""
        category = get_object_or_404(
            Category.objects.select_related('project'), pk=raw_category_id,
        )
        if project is not None and category.project_id != project.pk:
            from rest_framework.exceptions import NotFound

            raise NotFound()
        scoping.project_or_404(
            self.request.user, self.role(), category.project_id,
        )
        return category

    def create(self, request):
        category = self.category_in_project(request.data.get('category_id'))
        scoping.require_owner(category.project, request.user, SCHEDULE_WRITE)
        todo = services.save_todo(category, request.data)
        return Response(TodoSerializer(todo).data, status=status.HTTP_201_CREATED)

    def partial_update(self, request, pk=None):
        todo = self.get_object()
        project = todo.category.project
        scoping.require_owner(project, request.user, SCHEDULE_WRITE)
        category = todo.category
        if 'category_id' in request.data:
            category = self.category_in_project(request.data.get('category_id'), project)
        todo = services.save_todo(category, request.data, todo=todo)
        return Response(TodoSerializer(todo).data)

    def destroy(self, request, pk=None):
        todo = self.get_object()
        scoping.require_owner(todo.category.project, request.user, SCHEDULE_WRITE)
        services.delete_todo(todo)
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=['post'])
    def done(self, request, pk=None):
        todo = self.get_object()
        scoping.require_owner_or_site_engineer(
            todo.category.project, request.user, self.role(), TICK_ONLY,
        )
        todo = services.set_todo_done(request.user, todo, as_bool(request.data.get('done')))
        return Response(TodoSerializer(todo).data)

    @action(detail=True, methods=['post'])
    def verify(self, request, pk=None):
        todo = self.get_object()
        scoping.require_owner(todo.category.project, request.user, VERIFY_ONLY)
        todo = services.verify_todo(request.user, todo)
        return Response(TodoSerializer(todo).data)

    @action(detail=True, methods=['post'])
    def unverify(self, request, pk=None):
        todo = self.get_object()
        scoping.require_owner(todo.category.project, request.user, VERIFY_ONLY)
        todo = services.unverify_todo(request.user, todo, request.data.get('reason'))
        return Response(TodoSerializer(todo).data)


class ClientViewSet(ScopedViewSet):
    """`clients/` — client records for the project form and the client-link.

    Reads stay staff-only (the project form picks `client_id`). Create and edit
    are the Admin/Owner active role's, per task 5.3; the Accountant keeps read
    access. There is no delete route: `Project.client` protects the row and a
    login link must be removable without destroying the record.
    """

    serializer_class = ClientSerializer

    def get_queryset(self):
        return Client.objects.select_related('user')

    def _require_writer(self):
        scoping.require_client_writer(self.role(), CLIENT_WRITE)

    def list(self, request):
        scoping.require_staff(self.role(), 'Client records are staff-only.')
        return Response(ClientSerializer(self.get_queryset(), many=True).data)

    def retrieve(self, request, pk=None):
        scoping.require_staff(self.role(), 'Client records are staff-only.')
        return Response(ClientSerializer(self.get_object()).data)

    def create(self, request):
        self._require_writer()
        client = services.create_client(request.user, request.data)
        return Response(
            ClientSerializer(client).data, status=status.HTTP_201_CREATED,
        )

    def partial_update(self, request, pk=None):
        self._require_writer()
        client = services.update_client(request.user, self.get_object(), request.data)
        return Response(ClientSerializer(client).data)

    def update(self, request, pk=None):
        return self.partial_update(request, pk)

    @action(detail=True, methods=['post'], url_path='link-user')
    def link_user(self, request, pk=None):
        """Attach a client-role portal login to this client (one per client)."""
        self._require_writer()
        client = services.link_client_user(
            request.user, self.get_object(), request.data.get('user_id'),
        )
        return Response(ClientSerializer(client).data)

    @action(detail=True, methods=['post'], url_path='unlink-user')
    def unlink_user(self, request, pk=None):
        self._require_writer()
        client = services.unlink_client_user(request.user, self.get_object())
        return Response(ClientSerializer(client).data)


class SiteViewSet(viewsets.ModelViewSet):
    """`sites/` — unchanged Phase 3 tenant; kept for `site_inventory`/`requisitions`."""

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


@api_view(['PUT'])
def user_assignments_view(request, pk):
    """`users/{id}/assignments/` — an admin replaces one user's projects."""
    if capabilities.active_role(request) != Role.ADMIN:
        raise NotAllowed('Admin role required.')
    target = get_object_or_404(User, pk=pk)
    rows = request.data.get('assignments') or []
    assignments = services.set_user_assignments(request.user, target, rows)
    return Response(ProjectAssignmentSerializer(assignments, many=True).data)
