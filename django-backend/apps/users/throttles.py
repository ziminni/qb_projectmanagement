"""Rate limits for the endpoints an attacker would hammer."""

import hashlib

from rest_framework.throttling import AnonRateThrottle, SimpleRateThrottle


class LoginRateThrottle(AnonRateThrottle):
    """Caps login attempts per IP (see REST_FRAMEWORK['DEFAULT_THROTTLE_RATES'])."""

    scope = 'login'


class AccountLoginRateThrottle(SimpleRateThrottle):
    """Caps login attempts per account, whatever the source IP.

    Keyed by the normalized (trimmed, lower-cased) submitted email, hashed so no
    address sits in a cache key. An unknown email is bucketed exactly like a real
    one, so a 429 never says whether the account exists.
    """

    scope = 'login_email'

    def get_cache_key(self, request, view):
        email = str(request.data.get('email') or '').strip().lower()
        if not email:
            # Nothing to key on; the per-IP throttle is the only cap left.
            return None
        return self.cache_format % {
            'scope': self.scope,
            'ident': hashlib.sha256(email.encode()).hexdigest(),
        }


class PasswordResetRateThrottle(AnonRateThrottle):
    """Caps password-reset requests per IP so the endpoint cannot be abused."""

    scope = 'password_reset'
