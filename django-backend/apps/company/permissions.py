"""Role-based DRF permissions for the company profile and its settings.

Both classes ask `apps/users/capabilities.py` about the caller's **active**
role, exactly like the Phase 1.1 permissions.
"""

from rest_framework.permissions import SAFE_METHODS, BasePermission

from ..users import capabilities
from ..users.models import Role

# DRF types BasePermission.has_permission as returning Literal[True]; an
# override necessarily returns a plain bool.
# pyright: reportIncompatibleMethodOverride=false


class IsAdminOrAnyRoleRead(BasePermission):
    """Any signed-in role (the Client included) reads; only Admin writes.

    The client portal prints the firm's name on billings, so the profile is
    not staff-only (`shared/widgets/app_pdf_button.dart:27`).
    """

    message = 'Admin role required to change this.'

    def has_permission(self, request, view):
        if not (request.user and request.user.is_authenticated):
            return False
        role = capabilities.active_role(request)
        if role is None:
            return False
        if request.method in SAFE_METHODS:
            return True
        return role == Role.ADMIN


class IsAdminOrStaffRead(BasePermission):
    """Staff roles read the settings; only Admin changes them."""

    message = 'Admin role required to change this.'

    def has_permission(self, request, view):
        if not (request.user and request.user.is_authenticated):
            return False
        role = capabilities.active_role(request)
        if role is None:
            return False
        if request.method in SAFE_METHODS:
            return role in capabilities.STAFF_ROLES
        return role == Role.ADMIN
