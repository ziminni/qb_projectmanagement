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
    'apps.users',
    'apps.projects',
    'apps.site_inventory',
    'apps.requisitions',
    'apps.financials',
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
# Static files
# =============================================
STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'


# =============================================
# Auth — Custom User model (roles: Admin, Project Manager,
# Site Supervisor, Engineer)
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
# =============================================
POS_API_BASE_URL = os.environ.get('POS_API_BASE_URL', 'http://host.docker.internal:8000')
POS_API_TIMEOUT = env_int('POS_API_TIMEOUT', 15)
POS_API_TOKEN = os.environ.get('POS_API_TOKEN', '')
POS_API_VERIFY_SSL = env_bool('POS_API_VERIFY_SSL', True)

# Lifetime of a digitally generated material release token.
RELEASE_TOKEN_TTL_HOURS = env_int('RELEASE_TOKEN_TTL_HOURS', 72)