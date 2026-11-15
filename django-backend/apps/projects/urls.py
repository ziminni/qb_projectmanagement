"""Projects app URL configuration (all routed under /api/v1/).

Phase 2 routes: `projects/` (+ `status/`, `resend/`, `assignments/`,
`categories/`, `todos/`), `project-assignments/` (+ `respond/`),
`project-requests/`, `categories/{id}/`, `todos/` (+ `done/`, `verify/`,
`unverify/`), `users/{id}/assignments/` and read-only `clients/`.

`contracts/`, `project-phases/` and `milestones/` are gone: the contract terms
became `Project` columns and the timeline became the WBS (decision 05).
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    CategoryViewSet,
    ClientViewSet,
    ProjectAssignmentViewSet,
    ProjectRequestViewSet,
    ProjectViewSet,
    SiteViewSet,
    TodoViewSet,
    user_assignments_view,
)

router = DefaultRouter()
router.register(r'sites', SiteViewSet, basename='site')
router.register(r'clients', ClientViewSet, basename='client')
router.register(r'projects', ProjectViewSet, basename='project')
router.register(
    r'project-assignments', ProjectAssignmentViewSet, basename='projectassignment',
)
router.register(r'project-requests', ProjectRequestViewSet, basename='projectrequest')
router.register(r'categories', CategoryViewSet, basename='category')
router.register(r'todos', TodoViewSet, basename='todo')

urlpatterns = [
    path(
        'users/<int:pk>/assignments/', user_assignments_view,
        name='user-assignments',
    ),
    path('', include(router.urls)),
]
