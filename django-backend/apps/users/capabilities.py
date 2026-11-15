"""The one place that answers "what may this role do?".

Every capability rule lives here so splitting Owner out of Admin, or adding a
role, is a single-file change. Permission classes and views must ask these
helpers rather than comparing role strings themselves.
"""

from rest_framework.exceptions import PermissionDenied

from .models import Role

# Canonical presentation/fallback order. A user's default active role is the
# first one they hold in this order.
ROLE_ORDER = (
    Role.ADMIN,
    Role.OWNER,
    Role.ACCOUNTANT,
    Role.SITE_ENGINEER,
    Role.CLIENT,
)

# Roles that see every project in the company (everyone else is scoped by
# project assignment in Phase 2).
ALL_PROJECTS_ROLES = frozenset({Role.ADMIN, Role.ACCOUNTANT})

# Roles whose active role may see internal peso figures (AppRole.seesFinance).
FINANCE_ROLES = frozenset({Role.OWNER, Role.ACCOUNTANT})

# Staff roles: everything except the client portal.
STAFF_ROLES = frozenset(set(ROLE_ORDER) - {Role.CLIENT})

ACTIVE_ROLE_HEADER = 'X-Active-Role'


class RoleNotHeld(PermissionDenied):
    """403 raised when `X-Active-Role` names a role the caller does not hold."""

    default_code = 'ROLE_NOT_HELD'
    default_detail = {'code': 'ROLE_NOT_HELD'}

    def __init__(self):
        super().__init__(detail={'code': 'ROLE_NOT_HELD'})


def clean_roles(roles):
    """Valid, de-duplicated role codes in canonical order (invalid ones dropped)."""
    wanted = {str(role) for role in roles or ()}
    return [role for role in ROLE_ORDER if role in wanted]


def held_roles(user):
    """Role codes `user` holds, in canonical order; superusers count as admin."""
    if not user or not user.is_authenticated:
        return []
    # No prefetch cache here on purpose: this runs at most once per request.
    codes = list(user.user_roles.values_list('role', flat=True))
    if user.is_superuser:
        codes.append(Role.ADMIN)
    return clean_roles(codes)


def default_role(user):
    """The role a user acts as when no `X-Active-Role` header is sent."""
    roles = held_roles(user)
    return roles[0] if roles else None


def active_role(request):
    """The caller's active role for this request, or None when they hold none.

    Raises `RoleNotHeld` (403 `{"code": "ROLE_NOT_HELD"}`) when the header
    names a role the caller does not hold. Cached on the request so a view and
    its permissions never re-query.
    """
    cached = getattr(request, '_active_role', False)
    if cached is not False:
        return cached

    roles = held_roles(getattr(request, 'user', None))
    requested = request.headers.get(ACTIVE_ROLE_HEADER, '').strip().lower()
    if requested:
        if requested not in roles:
            raise RoleNotHeld()
        role = requested
    else:
        role = roles[0] if roles else None

    request._active_role = role
    return role


def sees_finance(role):
    """Whether the active role may see internal peso figures."""
    return role in FINANCE_ROLES


def sees_all_projects(role):
    """Whether the active role sees every project, not just assigned ones."""
    return role in ALL_PROJECTS_ROLES
