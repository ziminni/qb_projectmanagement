"""Server-side helpers: audit rows, notifications, and temporary passwords.

Nothing here is reachable from a client request body: audit rows and
notifications are only ever written by server code, so the desktop client
cannot forge them.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false

import logging
import secrets

import requests
from django.conf import settings
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.mail import send_mail

from . import email_templates
from .models import AuditLog, Notification, Role, User

logger = logging.getLogger(__name__)

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


def generate_reset_code():
    """Generate a 6-digit numeric password reset code."""
    return f'{secrets.randbelow(1_000_000):06d}'


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


def is_email_configured():
    """Return True when an HTTPS webhook/email API or SMTP host is configured."""
    return bool(
        getattr(settings, 'EMAIL_WEBHOOK_URL', '')
        or getattr(settings, 'BREVO_API_KEY', '')
        or getattr(settings, 'RESEND_API_KEY', '')
        or settings.EMAIL_HOST
    )


def _deliver_email(subject, body, recipient_email, *, html_body=None):
    """Send one email (plain text + optional HTML) via HTTPS webhook,
    Brevo/Resend HTTPS API, or Django SMTP.

    When no email provider is configured, returns ``(False, None)`` cleanly so
    the app uses its built-in in-app handoff flow with no error banner.
    """
    webhook_url = getattr(settings, 'EMAIL_WEBHOOK_URL', '')
    if webhook_url:
        try:
            payload = {
                'to': recipient_email,
                'subject': subject,
                'body': body,
            }
            if html_body:
                payload['html'] = html_body
            secret = getattr(settings, 'EMAIL_WEBHOOK_SECRET', '')
            if secret:
                payload['secret'] = secret
            resp = requests.post(
                webhook_url,
                json=payload,
                timeout=getattr(settings, 'EMAIL_TIMEOUT', 15),
                allow_redirects=True,
            )
            if 200 <= resp.status_code < 300:
                return True, None
            err = f'Email webhook HTTP {resp.status_code}: {resp.text[:200]}'
            logger.warning('Failed to send email to %s via webhook: %s', recipient_email, err)
            return False, err
        except Exception as exc:
            logger.warning('Failed to send email to %s via webhook: %s', recipient_email, exc)
            return False, str(exc)

    brevo_key = getattr(settings, 'BREVO_API_KEY', '')
    if brevo_key:
        try:
            brevo_payload = {
                'sender': {
                    'name': 'Queen Builders CPMS',
                    'email': settings.DEFAULT_FROM_EMAIL,
                },
                'to': [{'email': recipient_email}],
                'subject': subject,
                'textContent': body,
            }
            if html_body:
                brevo_payload['htmlContent'] = html_body
            resp = requests.post(
                'https://api.brevo.com/v3/smtp/email',
                headers={
                    'api-key': brevo_key,
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                },
                json=brevo_payload,
                timeout=getattr(settings, 'EMAIL_TIMEOUT', 15),
            )
            if 200 <= resp.status_code < 300:
                return True, None
            err = f'Brevo HTTP {resp.status_code}: {resp.text[:200]}'
            logger.warning('Failed to send email to %s via Brevo: %s', recipient_email, err)
            return False, err
        except Exception as exc:
            logger.warning('Failed to send email to %s via Brevo: %s', recipient_email, exc)
            return False, str(exc)

    resend_key = getattr(settings, 'RESEND_API_KEY', '')
    if resend_key:
        try:
            resend_payload = {
                'from': settings.DEFAULT_FROM_EMAIL,
                'to': [recipient_email],
                'subject': subject,
                'text': body,
            }
            if html_body:
                resend_payload['html'] = html_body
            resp = requests.post(
                'https://api.resend.com/emails',
                headers={
                    'Authorization': f'Bearer {resend_key}',
                    'Content-Type': 'application/json',
                },
                json=resend_payload,
                timeout=getattr(settings, 'EMAIL_TIMEOUT', 15),
            )
            if 200 <= resp.status_code < 300:
                return True, None
            err = f'Resend HTTP {resp.status_code}: {resp.text[:200]}'
            logger.warning('Failed to send email to %s via Resend: %s', recipient_email, err)
            return False, err
        except Exception as exc:
            logger.warning('Failed to send email to %s via Resend: %s', recipient_email, exc)
            return False, str(exc)

    if not settings.EMAIL_HOST:
        # Email delivery is intentionally off: return (False, None) so the UI
        # presents the manual/in-app credential handoff cleanly without an error.
        return False, None

    try:
        sent = send_mail(
            subject=subject,
            message=body,
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[recipient_email],
            html_message=html_body,
            fail_silently=False,
        )
        return bool(sent), None
    except Exception as exc:
        logger.warning('Failed to send email to %s via SMTP: %s', recipient_email, exc)
        return False, str(exc)


def send_credentials_email(user, temporary_password, *, is_reset=False):
    """Send the user's email + temporary password to their inbox.

    Returns ``(sent: bool, error: str | None)``.
    """
    subject, plain_text, html_body = email_templates.render_credentials_email(
        user, temporary_password, is_reset=is_reset,
    )
    return _deliver_email(subject, plain_text, user.email, html_body=html_body)


def send_password_reset_code_email(user, code, *, expires_minutes=15):
    """Email a 6-digit password reset code to `user`.

    Returns ``(sent: bool, error: str | None)``.
    """
    subject, plain_text, html_body = email_templates.render_password_reset_code_email(
        user, code, expires_minutes=expires_minutes,
    )
    return _deliver_email(subject, plain_text, user.email, html_body=html_body)


def notify_admins(type, message, link=None):
    """Notify every active user currently holding the admin role."""
    admins = User.objects.filter(is_active=True, user_roles__role=Role.ADMIN).distinct()
    return [notify(admin, type, message, link=link) for admin in admins]
