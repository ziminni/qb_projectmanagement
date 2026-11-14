"""Rate limits for the endpoints an attacker would hammer."""

from rest_framework.throttling import AnonRateThrottle


class LoginRateThrottle(AnonRateThrottle):
    """Caps login attempts per IP (see REST_FRAMEWORK['DEFAULT_THROTTLE_RATES'])."""

    scope = 'login'


class PasswordResetRateThrottle(AnonRateThrottle):
    """Caps password-reset requests per IP so the endpoint cannot be abused."""

    scope = 'password_reset'
