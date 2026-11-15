"""Reusable role-based DRF permissions for the CPMS modules.

Every check asks `capabilities` about the caller's **active** role (the
`X-Active-Role` header, else their first role in the canonical order), so a
header naming a role the caller does not hold fails with
`403 {"code": "ROLE_NOT_HELD"}` instead of silently widening access.
"""

from rest_framework.permissions import SAFE_METHODS, BasePermission

from . import capabilities
from .models import Role

# DRF annotates BasePermission.has_permission as returning Literal[True]; every
# override necessarily returns a plain bool, hence the ignore on each override.


def _active_role(request):
    """Active role for this request, or None when the caller holds no role."""
    if not (request.user and request.user.is_authenticated):
        return None
    return capabilities.active_role(request)


class IsAdmin(BasePermission):
    """Allows access only to Admin-role users (or Django superusers)."""

    message = 'Admin role required.'

    def has_permission(self, request, view):  # pyright: ignore[reportIncompatibleMethodOverride]
        return _active_role(request) == Role.ADMIN


class IsAdminOrReadOnly(BasePermission):
    """Any staff (non-client) active role may read; only Admin may write."""

    message = 'Admin role required to change this.'

    def has_permission(self, request, view):  # pyright: ignore[reportIncompatibleMethodOverride]
        role = _active_role(request)
        if role is None:
            return False
        if request.method in SAFE_METHODS:
            return role in capabilities.STAFF_ROLES
        return role == Role.ADMIN


class IsProjectManagerOrAdmin(BasePermission):
    """Gates approval-style actions (e.g. requisition approval)."""

    message = 'Project Manager or Admin role required.'

    def has_permission(self, request, view):  # pyright: ignore[reportIncompatibleMethodOverride]
        return _active_role(request) in (Role.ADMIN, Role.OWNER)


class IsFieldStaff(BasePermission):
    """Allows the on-site roles that raise material requests."""

    message = 'Field staff (Site Engineer) role required.'

    def has_permission(self, request, view):  # pyright: ignore[reportIncompatibleMethodOverride]
        return _active_role(request) in (Role.SITE_ENGINEER, Role.ADMIN)


class IsStaffOrSelfRead(BasePermission):
    """Staff read the user directory; a client may read only their own row.

    List-style actions stay staff-only (a client cannot enumerate the firm),
    while `retrieve` is allowed and the viewset scopes the queryset to the
    caller. Writes remain admin-only.
    """

    message = 'Staff role required.'

    def has_permission(self, request, view):  # pyright: ignore[reportIncompatibleMethodOverride]
        role = _active_role(request)
        if role is None:
            return False
        if request.method in SAFE_METHODS:
            if role in capabilities.STAFF_ROLES:
                return True
            return getattr(view, 'action', None) == 'retrieve'
        return role == Role.ADMIN
