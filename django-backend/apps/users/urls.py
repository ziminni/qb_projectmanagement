"""Users app URL configuration (all routed under /api/v1/).

`auth/register/` no longer exists on purpose: accounts are created by an
admin through `POST users/`.
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    AuditLogListView,
    NotificationListView,
    UserRoleListView,
    UserViewSet,
    change_password_view,
    login_view,
    logout_view,
    me_view,
    notification_read_view,
    notifications_read_all_view,
    password_reset_request_view,
)

router = DefaultRouter()
router.register(r'users', UserViewSet, basename='user')

urlpatterns = [
    path('auth/login/', login_view, name='auth-login'),
    path('auth/refresh/', TokenRefreshView.as_view(), name='auth-refresh'),
    path('auth/logout/', logout_view, name='auth-logout'),
    path('auth/me/', me_view, name='auth-me'),
    path('auth/change-password/', change_password_view, name='auth-change-password'),
    path('auth/password-reset-request/', password_reset_request_view,
         name='auth-password-reset-request'),

    path('user-roles/', UserRoleListView.as_view(), name='user-role-list'),
    path('audit-logs/', AuditLogListView.as_view(), name='audit-log-list'),

    path('notifications/', NotificationListView.as_view(), name='notification-list'),
    path('notifications/read-all/', notifications_read_all_view,
         name='notification-read-all'),
    path('notifications/<int:pk>/read/', notification_read_view,
         name='notification-read'),

    path('', include(router.urls)),
]
