"""Users app URL configuration (all routed under /api/v1/).

`auth/register/` no longer exists on purpose: accounts are created by an
admin through `POST users/`.
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from .system_views import (
    system_backup_download_view,
    system_backup_restore_view,
    system_backup_schedule_view,
    system_backup_upload_restore_view,
    system_backups_view,
    system_health_view,
    system_pos_retry_view,
    system_security_policy_view,
    system_security_view,
    system_session_revoke_view,
    system_sessions_revoke_all_view,
)
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

    path('system/security/', system_security_view, name='system-security'),
    path('system/security/sessions/revoke-all/',
         system_sessions_revoke_all_view, name='system-sessions-revoke-all'),
    path('system/security/sessions/<int:pk>/revoke/',
         system_session_revoke_view, name='system-session-revoke'),
    path('system/security/policy/', system_security_policy_view,
         name='system-security-policy'),
    path('system/backups/', system_backups_view, name='system-backups'),
    path('system/backups/restore/', system_backup_restore_view,
         name='system-backup-restore'),
    path('system/backups/upload-restore/', system_backup_upload_restore_view,
         name='system-backup-upload-restore'),
    path('system/backups/schedule/', system_backup_schedule_view,
         name='system-backup-schedule'),
    path('system/backups/<str:backup_id>/download/',
         system_backup_download_view, name='system-backup-download'),
    path('system/health/', system_health_view, name='system-health'),
    path('system/pos-sync/<int:job_id>/retry/',
         system_pos_retry_view, name='system-pos-retry'),

    path('', include(router.urls)),
]
