"""
BuildPro CPMS — User model and construction-firm role taxonomy.

Uses username as the primary login identifier (consistent with Repo #1 / POS)
so credentials and habits carry across the two systems.

ERD mapping:
    USER → apps_users.User   (role enum below)
    ROLE → apps_users.User.role
"""

from django.contrib.auth.models import (
    AbstractBaseUser,
    BaseUserManager,
    PermissionsMixin,
)
from django.db import models


class UserRole(models.TextChoices):
    """Roles across the construction firm."""

    ADMIN = 'ADMIN', 'Admin'
    PROJECT_MANAGER = 'PROJECT_MANAGER', 'Project Manager'
    SITE_SUPERVISOR = 'SITE_SUPERVISOR', 'Site Supervisor'
    ENGINEER = 'ENGINEER', 'Engineer'


class UserManager(BaseUserManager):
    """Custom manager: username is the unique login identifier."""

    def _create_user(self, username, email, password, **extra_fields):
        if not username:
            raise ValueError('Username is required')
        if not email:
            raise ValueError('Email is required')
        email = self.normalize_email(email)
        user = self.model(username=username, email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, username, email=None, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', False)
        extra_fields.setdefault('is_superuser', False)
        extra_fields.setdefault('role', UserRole.ENGINEER)
        return self._create_user(username, email, password, **extra_fields)

    def create_superuser(self, username, email=None, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('role', UserRole.ADMIN)
        if not extra_fields.get('is_staff'):
            raise ValueError('Superuser must have is_staff=True.')
        if not extra_fields.get('is_superuser'):
            raise ValueError('Superuser must have is_superuser=True.')
        return self._create_user(username, email, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    """Custom User with an explicit construction-firm role.

    Django's Group/Permission RBAC remains available via PermissionsMixin;
    `role` is the coarse, domain-level gate used by the CPMS modules while
    fine-grained permissions stay in auth_group / auth_permission.
    """

    username = models.CharField(
        max_length=150,
        unique=True,
        help_text='Required. Primary login identifier.',
    )
    email = models.EmailField(unique=True)
    first_name = models.CharField(max_length=150, blank=True)
    last_name = models.CharField(max_length=150, blank=True)
    role = models.CharField(
        max_length=32,
        choices=UserRole.choices,
        default=UserRole.ENGINEER,
        db_index=True,
    )
    phone = models.CharField(max_length=32, blank=True)
    employee_no = models.CharField(
        max_length=32,
        blank=True,
        help_text='Firm-issued employee number.',
    )

    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(
        default=False,
        help_text='Grants access to the Django admin site.',
    )

    date_joined = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserManager()

    USERNAME_FIELD = 'username'
    REQUIRED_FIELDS = ['email']

    class Meta:
        verbose_name = 'User'
        verbose_name_plural = 'Users'
        ordering = ('username',)

    def __str__(self):
        return f'{self.username} ({self.get_role_display()})'

    @property
    def full_name(self):
        """Human-readable name, falling back to the username."""
        name = f'{self.first_name} {self.last_name}'.strip()
        return name or self.username

    # --- Role helpers (used by views/permissions) ---
    @property
    def is_admin(self):
        return self.role == UserRole.ADMIN or self.is_superuser

    @property
    def is_project_manager(self):
        return self.role == UserRole.PROJECT_MANAGER

    @property
    def is_site_supervisor(self):
        return self.role == UserRole.SITE_SUPERVISOR

    @property
    def is_engineer(self):
        return self.role == UserRole.ENGINEER

    def can_approve_requisitions(self):
        """Only Admin and Project Manager may approve material requests."""
        return self.is_admin or self.is_project_manager