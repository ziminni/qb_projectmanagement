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


# =============================================
# Security
# =============================================
SECRET_KEY = os.environ.get(
    'DJANGO_SECRET_KEY',
    'django-insecure-cpms-dev-only-key-change-me-in-production',
)

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
    # Caps the two endpoints an attacker would hammer (apps/users/throttles.py).
    'DEFAULT_THROTTLE_RATES': {
        'login': '10/min',
        'password_reset': '5/min',
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
# Dev-only convenience; switch to CORS_ALLOWED_ORIGINS in production.
# =============================================
CORS_ALLOW_ALL_ORIGINS = env_bool('CORS_ALLOW_ALL_ORIGINS', True)
CORS_ALLOWED_ORIGINS = [
    o.strip()
    for o in os.environ.get('CORS_ALLOWED_ORIGINS', '').split(',')
    if o.strip()
]


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
POS_OUTBOX_POLL_SECONDS = env_int('POS_OUTBOX_POLL_SECONDS', 30)
# A read-back older than this is reported `stale` on `pos-status/`.
POS_STATUS_STALE_AFTER_SECONDS = env_int('POS_STATUS_STALE_AFTER_SECONDS', 300)

# Lifetime of a digitally generated material release token.
RELEASE_TOKEN_TTL_HOURS = env_int('RELEASE_TOKEN_TTL_HOURS', 72)