"""Master-data permission: staff read the lists, Admin and Project Manager write.

The desktop reaches this page as `admin` ("Master lists") and as `owner`
("Price lists"); `accountant` and `site_engineer` only consume the lists.
"""

from rest_framework.permissions import SAFE_METHODS, BasePermission

from ..users import capabilities
from ..users.models import Role

# DRF types BasePermission.has_permission as returning Literal[True]; an
# override necessarily returns a plain bool.
# pyright: reportIncompatibleMethodOverride=false


class IsMasterDataWriter(BasePermission):
    """Any staff role may read; only Admin or Project Manager (owner) may change."""

    message = 'Project Manager or Admin role required to change this.'

    def has_permission(self, request, view):
        if not (request.user and request.user.is_authenticated):
            return False
        role = capabilities.active_role(request)
        if role is None:
            return False
        if request.method in SAFE_METHODS:
            return role in capabilities.STAFF_ROLES
        return role in (Role.ADMIN, Role.OWNER)
