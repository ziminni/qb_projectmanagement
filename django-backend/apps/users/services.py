"""Server-side helpers: audit rows, notifications, and temporary passwords.

Nothing here is reachable from a client request body: audit rows and
notifications are only ever written by server code, so the desktop client
cannot forge them.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false

import secrets

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError

from .models import AuditLog, Notification, Role, User

# No look-alike glyphs (0/O, 1/l/I): an admin reads the temporary password out
# loud to the user who has to type it in.
TEMPORARY_CHARS = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
TEMPORARY_PASSWORD_LENGTH = 12


def generate_temporary_password():
    """Generate a password that passes the rules below by construction."""
    while True:
        password = ''.join(
            secrets.choice(TEMPORARY_CHARS)
            for _ in range(TEMPORARY_PASSWORD_LENGTH)
        )
        if password_rules_error(password) is None:
            return password


def password_rules_error(password, user=None):
    """Return the first rule `password` breaks, or None when it is acceptable."""
    if len(password) < 8:
        return 'Use at least 8 characters.'
    if not any(char.isalpha() for char in password) or not any(
        char.isdigit() for char in password
    ):
        return 'Use at least one letter and one digit.'
    try:
        validate_password(password, user)
    except ValidationError as error:
        return ' '.join(str(message) for message in error.messages)
    return None


def record(user, action, entity, entity_id, details=None):
    """Write one audit row. Call inside the transaction of the change itself."""
    return AuditLog.objects.create(
        user=user,
        action=action,
        entity=entity,
        entity_id=entity_id,
        details=details or {},
    )


def notify(user, type, message, link=None):
    """Create one in-app notification for `user`."""
    return Notification.objects.create(
        user=user,
        type=type,
        message=message,
        link=link,
    )


def notify_admins(type, message, link=None):
    """Notify every active user currently holding the admin role."""
    admins = User.objects.filter(is_active=True, user_roles__role=Role.ADMIN).distinct()
    return [notify(admin, type, message, link=link) for admin in admins]
