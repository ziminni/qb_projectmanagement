"""Labor URL configuration (routed under /api/v1/).

Phase 4:

* `workers/` — staff picker (`?active_only=`) plus owner/accountant
  create/update; no delete;
* `attendance/?project=&from=&to=` — project-scoped reads;
* `attendance/save-day/` — the atomic partial-sheet write, refused inside a
  processed payroll period;
* `payroll-periods/` — the cut-off calendar plus `verify/`, `cash-advance/`,
  `lines/` and `process/`;
* `labor-cost/?project=` — gross pay of the project's processed periods.
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .payroll_views import LaborCostView, PayrollPeriodViewSet
from .views import AttendanceViewSet, WorkerViewSet

router = DefaultRouter()
router.register(r'workers', WorkerViewSet, basename='worker')
router.register(r'attendance', AttendanceViewSet, basename='attendance')
router.register(r'payroll-periods', PayrollPeriodViewSet,
                basename='payroll-period')

urlpatterns = [
    path('labor-cost/', LaborCostView.as_view(), name='labor-cost'),
    path('', include(router.urls)),
]
