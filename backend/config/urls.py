"""
URL configuration for the BuildPro CPMS backend.

Namespaced under /api/v1/ for future versioning, matching Repo #1 (POS).
"""

from django.contrib import admin
from django.urls import include, path
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response


@api_view(['GET'])
@permission_classes([AllowAny])
def health_check(request):
    """Liveness probe — also used by the POS backend to verify CPMS reachability."""
    return Response({
        'status': 'ok',
        'service': 'BuildPro CPMS',
        'system': 'cpms',
    })


urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/health/', health_check, name='health'),

    # Domain module routes (v1 namespace for future versioning)
    path('api/v1/', include('apps.users.urls')),
    path('api/v1/', include('apps.projects.urls')),
    path('api/v1/', include('apps.site_inventory.urls')),
    path('api/v1/', include('apps.requisitions.urls')),
    path('api/v1/', include('apps.financials.urls')),
]