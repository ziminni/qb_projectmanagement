"""Company app URL configuration (all routed under /api/v1/).

Both endpoints are singletons of the caller's own company — there is no id in
the path, so one company can never read or write another's row.
"""

from django.urls import path

from .views import CompanySettingsView, CompanyView

urlpatterns = [
    path('company/', CompanyView.as_view(), name='company'),
    path('company-settings/', CompanySettingsView.as_view(), name='company-settings'),
]
