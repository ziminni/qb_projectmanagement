"""
Django settings for the BuildPro CPMS backend.

Repo #2 of the BuildPro dual-entity ecosystem:
    Repo #1  qb_pos_inventory_system  -> Hardware Store POS  (host :8000, DB :5433)
    Repo #2  qb_project_management_system -> Construction CPMS (host :8001, DB :5434)

Values are read from the environment so the same image runs inside Docker
(DB host `db`) and against a local Postgres. Defaults are dev-safe and mirror
the conventions used by Repo #1.
"""

import os
from datetime import timedelta
from pathlib import Path

try:
    import certifi

    # Windows Server VMs often lack updated root CAs in the OS store, causing
    # SMTP STARTTLS (e.g. smtp.gmail.com) to fail with CERTIFICATE_VERIFY_FAILED.
    # Point Python's default SSL context at certifi's Mozilla CA bundle.
    os.environ.setdefault('SSL_CERT_FILE', certifi.where())
except ImportError:
    pass

from corsheaders.defaults import default_headers
from django.core.exceptions import ImproperlyConfigured


def env_bool(name, default=False):
    """Parse a boolean environment variable ('1', 'true', 'yes' → True)."""
    return os.environ.get(name, str(default)).strip().lower() in ('1', 'true', 'yes', 'on')


def env_int(name, default):
    """Parse an int environment variable, failing loudly on a malformed value.

    Raises ImproperlyConfigured rather than a bare ValueError so a typo in
    .env names the offending variable instead of surfacing as an opaque
    crash during settings import.
    """
    raw = os.environ.get(name, str(default))
    try:
        return int(raw)
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(
            f'Environment variable {name!r} must be an integer, got {raw!r}.'
        ) from exc


# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent


def _load_dotenv(path):
    """Load key=value pairs from `.env` without overwriting real env vars."""
    if not path.is_file():
        return
    try:
        lines = path.read_text(encoding='utf-8').splitlines()
    except OSError:
        return
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        if key:
            os.environ.setdefault(key, value)


_load_dotenv(BASE_DIR / '.env')


# =============================================
# Security
# =============================================
# Outside DEBUG this value is refused (see "Production mode" below), so a
# copy-pasted .env can never reach a public host.
DEV_INSECURE_SECRET_KEY = 'django-insecure-cpms-dev-only-key-change-me-in-production'  # noqa: S105 - shipped dev default, refused in production

SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY', DEV_INSECURE_SECRET_KEY)

DEBUG = env_bool('DJANGO_DEBUG', True)

ALLOWED_HOSTS = [
    h.strip()
    for h in os.environ.get('DJANGO_ALLOWED_HOSTS', '*').split(',')
    if h.strip()
]


# =============================================
# Application definition
# =============================================
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',

    # Third-party
    'rest_framework',
    'corsheaders',
    # Required for BLACKLIST_AFTER_ROTATION and logout-time token revocation.
    'rest_framework_simplejwt.token_blacklist',

    # BuildPro CPMS Modules (domain-driven)
    'apps.company',
    'apps.users',
    'apps.projects',
    'apps.site_inventory',
    'apps.requisitions',
    'apps.financials',
    'apps.master_data',
    'apps.site_reports',
    'apps.labor',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'
ASGI_APPLICATION = 'config.asgi.application'


# =============================================
# Database (PostgreSQL 15 in Docker, service name `db`)
# =============================================
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.environ.get('POSTGRES_DB', 'buildpro_cpms'),
        'USER': os.environ.get('POSTGRES_USER', 'admin'),
        'PASSWORD': os.environ.get('POSTGRES_PASSWORD', 'adminpassword'),
        'HOST': os.environ.get('POSTGRES_HOST', 'db'),
        'PORT': os.environ.get('POSTGRES_PORT', '5432'),
        'CONN_MAX_AGE': env_int('POSTGRES_CONN_MAX_AGE', 60),
    }
}


# =============================================
# Password validation
# =============================================
AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]


# =============================================
# Internationalization
# =============================================
LANGUAGE_CODE = 'en-us'

TIME_ZONE = 'Asia/Manila'

USE_I18N = True

USE_TZ = True


# =============================================
# Private uploads — project documents and report photos
# =============================================
# Files live outside STATIC_ROOT and are served only by the API, which re-checks
# the JWT, the active role and the project scope on every download (contract
# "Uploads"). MEDIA_URL is deliberately not mounted in config/urls.py, so this
# path answers 404.
MEDIA_ROOT = Path(os.environ.get('DJANGO_MEDIA_ROOT', str(BASE_DIR / 'private_media')))
MEDIA_URL = '/api/v1/private-media/'

# Caps from decision 06 #7: documents 25 MB, report photos 10 MB.
DOCUMENT_UPLOAD_MAX_BYTES = env_int('DOCUMENT_UPLOAD_MAX_BYTES', 25 * 1024 * 1024)
PHOTO_UPLOAD_MAX_BYTES = env_int('PHOTO_UPLOAD_MAX_BYTES', 10 * 1024 * 1024)

# Refuse an oversized body before Django buffers it; the per-view size check
# adds the exact refusal text. Files above FILE_UPLOAD_MAX_MEMORY_SIZE spool to
# a temporary file instead of RAM.
DATA_UPLOAD_MAX_MEMORY_SIZE = env_int(
    'DATA_UPLOAD_MAX_MEMORY_SIZE', DOCUMENT_UPLOAD_MAX_BYTES + 2 * 1024 * 1024,
)
FILE_UPLOAD_MAX_MEMORY_SIZE = env_int(
    'FILE_UPLOAD_MAX_MEMORY_SIZE', 2_621_440,
)


# =============================================
# Static files
# =============================================
STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'


# =============================================
# Email (SMTP when EMAIL_HOST is configured; console backend otherwise)
# =============================================
EMAIL_HOST = os.environ.get('EMAIL_HOST', '').strip()
EMAIL_PORT = env_int('EMAIL_PORT', 587)
EMAIL_HOST_USER = os.environ.get('EMAIL_HOST_USER', '').strip()
EMAIL_HOST_PASSWORD = os.environ.get('EMAIL_HOST_PASSWORD', '').strip()
EMAIL_USE_SSL = os.environ.get('EMAIL_USE_SSL', 'false').lower() in ('1', 'true', 'yes')
EMAIL_USE_TLS = (
    False
    if EMAIL_USE_SSL
    else os.environ.get('EMAIL_USE_TLS', 'true').lower() in ('1', 'true', 'yes')
)
EMAIL_TIMEOUT = env_int('EMAIL_TIMEOUT', 15)
EMAIL_WEBHOOK_URL = os.environ.get('EMAIL_WEBHOOK_URL', '').strip()
EMAIL_WEBHOOK_SECRET = os.environ.get('EMAIL_WEBHOOK_SECRET', '').strip()
BREVO_API_KEY = os.environ.get('BREVO_API_KEY', '').strip()
RESEND_API_KEY = os.environ.get('RESEND_API_KEY', '').strip()
DEFAULT_FROM_EMAIL = os.environ.get(
    'DEFAULT_FROM_EMAIL',
    EMAIL_HOST_USER or 'noreply@queenbuilders.local',
)
EMAIL_BACKEND = os.environ.get(
    'EMAIL_BACKEND',
    'django.core.mail.backends.smtp.EmailBackend'
    if EMAIL_HOST
    else 'django.core.mail.backends.console.EmailBackend',
)


# =============================================
# Auth — Custom User model (email login; roles admin, owner,
# site_engineer, accountant, client via the user_roles junction)
# =============================================
AUTH_USER_MODEL = 'apps_users.User'


# =============================================
# Django REST Framework
# =============================================
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    'DEFAULT_PAGINATION_CLASS': 'rest_framework.pagination.PageNumberPagination',
    'PAGE_SIZE': 50,
    # Baseline caps for every endpoint; the auth routes add their own scopes
    # (apps/users/throttles.py). Rates are env-overridable so a demo host can be
    # loosened without a code change.
    'DEFAULT_THROTTLE_CLASSES': (
        'rest_framework.throttling.AnonRateThrottle',
        'rest_framework.throttling.UserRateThrottle',
    ),
    'DEFAULT_THROTTLE_RATES': {
        'anon': os.environ.get('THROTTLE_ANON', '60/min'),
        'user': os.environ.get('THROTTLE_USER', '1000/hour'),
        'login': os.environ.get('THROTTLE_LOGIN', '10/min'),
        'login_email': os.environ.get('THROTTLE_LOGIN_EMAIL', '5/min'),
        'password_reset': os.environ.get('THROTTLE_PASSWORD_RESET', '5/min'),
    },
}


# =============================================
# Simple JWT — shared token contract with the POS backend
# =============================================
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(hours=8),   # matches a full site work shift
    'REFRESH_TOKEN_LIFETIME': timedelta(days=7),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'AUTH_HEADER_TYPES': ('Bearer',),
}


# =============================================
# CORS — allows the Flutter client and the POS service to call this API.
# Wildcard is the dev convenience; production must name its origins.
# =============================================
CORS_ALLOW_ALL_ORIGINS = env_bool('CORS_ALLOW_ALL_ORIGINS', True)
# The desktop/web client sends the active role in a custom header; a browser only
# sends it when the preflight allows it. Extend the defaults, never replace them.
CORS_ALLOW_HEADERS = (*default_headers, 'x-active-role')
CORS_ALLOWED_ORIGINS = [
    o.strip()
    for o in os.environ.get('CORS_ALLOWED_ORIGINS', '').split(',')
    if o.strip()
]


# =============================================
# Production mode — fail closed
# =============================================
# DEBUG is the only switch. With DJANGO_DEBUG=false the dev conveniences above
# are refused loudly at import time instead of quietly shipping an open API.
if not DEBUG:
    problems = []
    if not os.environ.get('DJANGO_SECRET_KEY', '').strip() \
            or SECRET_KEY == DEV_INSECURE_SECRET_KEY:
        problems.append(
            'DJANGO_SECRET_KEY is unset or still the shipped dev default. Generate one: '
            "python -c 'import secrets; print(secrets.token_urlsafe(64))'"
        )
    if '*' in ALLOWED_HOSTS or not ALLOWED_HOSTS:
        problems.append(
            'DJANGO_ALLOWED_HOSTS is "*" (or empty). Name the host(s) that serve the API, '
            'e.g. DJANGO_ALLOWED_HOSTS=cpms.example.com'
        )
    if CORS_ALLOW_ALL_ORIGINS:
        problems.append(
            'CORS_ALLOW_ALL_ORIGINS is true. Set CORS_ALLOW_ALL_ORIGINS=False and list '
            'CORS_ALLOWED_ORIGINS=https://<host>'
        )
    if problems:
        raise ImproperlyConfigured(
            'Refusing to start with DJANGO_DEBUG=false until every problem below is fixed:\n- '
            + '\n- '.join(problems)
        )

    # Cloudflare Quick Tunnel terminates TLS and forwards plain http with
    # X-Forwarded-Proto, so Django must trust that header to see the request as
    # secure. https://docs.djangoproject.com/en/5.2/ref/settings/#secure-proxy-ssl-header
    SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = env_int('SECURE_HSTS_SECONDS', 31536000)
    SECURE_HSTS_INCLUDE_SUBDOMAINS = env_bool('SECURE_HSTS_INCLUDE_SUBDOMAINS', False)
    SECURE_HSTS_PRELOAD = False
    # No SECURE_SSL_REDIRECT: the tunnel origin and the internal health probe
    # speak plain http, and a redirect would break both. TLS ends at Cloudflare.
else:
    SESSION_COOKIE_SECURE = False
    CSRF_COOKIE_SECURE = False
    SECURE_HSTS_SECONDS = 0
    SECURE_PROXY_SSL_HEADER = None


# =============================================
# POS integration (Repo #1)
# host.docker.internal is wired via docker-compose extra_hosts so the CPMS
# container can reach the POS API published on the host.
#
# Task 3.1b (contract `phase-3-procurement.md` "3.1b Built as"): the bridge
# authenticates as the POS `CPMS Service` account with a rotating JWT minted
# from these service credentials. There is deliberately **no static
# `POS_API_TOKEN`** any more — the legacy client that used it is gone.
# =============================================
POS_API_BASE_URL = os.environ.get('POS_API_BASE_URL', 'http://host.docker.internal:8000')
POS_API_TIMEOUT = env_int('POS_API_TIMEOUT', 15)
POS_API_VERIFY_SSL = env_bool('POS_API_VERIFY_SSL', True)
POS_API_SERVICE_USERNAME = os.environ.get('POS_API_SERVICE_USERNAME', '')
POS_API_SERVICE_PASSWORD = os.environ.get('POS_API_SERVICE_PASSWORD', '')
# HTTPS is required; plain http is accepted only for a local/LAN host when this
# is set explicitly (dev convenience, never for a public origin).
POS_API_ALLOW_INSECURE_LOCAL = env_bool('POS_API_ALLOW_INSECURE_LOCAL', False)
# Optional deployment gateway header (backend-only; never logged, never sent to
# the desktop client). Not a replacement for the JWT.
POS_API_GATEWAY_HEADER_NAME = os.environ.get('POS_API_GATEWAY_HEADER_NAME', '')
POS_API_GATEWAY_HEADER_VALUE = os.environ.get('POS_API_GATEWAY_HEADER_VALUE', '')

# Durable outbox behaviour (management command `run_pos_outbox`).
POS_OUTBOX_MAX_ATTEMPTS = env_int('POS_OUTBOX_MAX_ATTEMPTS', 5)
POS_OUTBOX_BACKOFF_SECONDS = env_int('POS_OUTBOX_BACKOFF_SECONDS', 30)
POS_OUTBOX_BACKOFF_MAX_SECONDS = env_int('POS_OUTBOX_BACKOFF_MAX_SECONDS', 3600)
POS_OUTBOX_POLL_SECONDS = env_int('POS_OUTBOX_POLL_SECONDS', 5)
POS_AUTO_REFRESH_SECONDS = env_int('POS_AUTO_REFRESH_SECONDS', 15)
# A read-back older than this is reported `stale` on `pos-status/`.
POS_STATUS_STALE_AFTER_SECONDS = env_int('POS_STATUS_STALE_AFTER_SECONDS', 300)

# Lifetime of a digitally generated material release token.
RELEASE_TOKEN_TTL_HOURS = env_int('RELEASE_TOKEN_TTL_HOURS', 72)