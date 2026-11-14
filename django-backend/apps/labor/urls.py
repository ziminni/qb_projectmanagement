"""Labor URL configuration (routed under /api/v1/).

Phase 4 slice A only:

* `workers/` — staff picker (`?active_only=`) plus owner/accountant
  create/update; no delete;
* `attendance/?project=&from=&to=` — project-scoped reads;
* `attendance/save-day/` — the atomic partial-sheet write.

Payroll routes are a later slice and are deliberately absent here.
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import AttendanceViewSet, WorkerViewSet

router = DefaultRouter()
router.register(r'workers', WorkerViewSet, basename='worker')
router.register(r'attendance', AttendanceViewSet, basename='attendance')

urlpatterns = [
    path('', include(router.urls)),
]
