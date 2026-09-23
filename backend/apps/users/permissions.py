"""Reusable role-based DRF permissions for the CPMS modules."""

from rest_framework.permissions import SAFE_METHODS, BasePermission

from .models import UserRole


class IsAdmin(BasePermission):
    """Allows access only to Admin-role users (or Django superusers)."""

    message = 'Admin role required.'

    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.is_admin)


class IsAdminOrReadOnly(BasePermission):
    """Any authenticated user may read; only Admin may write."""

    def has_permission(self, request, view):
        if not (request.user and request.user.is_authenticated):
            return False
        if request.method in SAFE_METHODS:
            return True
        return request.user.is_admin


class IsProjectManagerOrAdmin(BasePermission):
    """Gates approval-style actions (e.g. requisition approval)."""

    message = 'Project Manager or Admin role required.'

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        return user.is_admin or user.role == UserRole.PROJECT_MANAGER


class IsFieldStaff(BasePermission):
    """Allows the on-site roles that raise material requests."""

    message = 'Field staff (Engineer or Site Supervisor) role required.'

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        return user.role in (UserRole.ENGINEER, UserRole.SITE_SUPERVISOR) or user.is_admin