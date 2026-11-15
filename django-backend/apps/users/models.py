"""CPMS users, the multi-role junction, the audit log and in-app notifications.

Login is by email (stored lower-case, unique case-insensitively). A user holds
one or more roles through `UserRole`; capability rules for those roles live in
`capabilities.py` so that file is the only place to edit when the role model
changes (e.g. splitting Owner out of Admin).

ERD mapping:
    USER          → apps_users.User
    USER_ROLE     → apps_users.UserRole (junction, one row per held role)
    AUDIT_LOG     → apps_users.AuditLog
    APP_NOTIFICATION → apps_users.Notification
"""

# Pyright here runs without django-stubs, so every model field is inferred as
# its `Field` class. This suppression only silences that inference gap.
# pyright: reportAssignmentType=false, reportAttributeAccessIssue=false, reportArgumentType=false, reportGeneralTypeIssues=false, reportIncompatibleVariableOverride=false

from django.contrib.auth.models import (
    AbstractBaseUser,
    BaseUserManager,
    PermissionsMixin,
)
from django.db import models
from django.db.models.functions import Lower


class Role(models.TextChoices):
    """Role codes in `user_roles.role` (mirror of Flutter `AppRole`)."""

    ADMIN = 'admin', 'Admin / Owner'
    OWNER = 'owner', 'Project Manager'
    SITE_ENGINEER = 'site_engineer', 'Site Engineer / Foreman'
    ACCOUNTANT = 'accountant', 'Accountant'
    CLIENT = 'client', 'Client'


class UserManager(BaseUserManager):
    """Custom manager: email is the unique login identifier."""

    def _create_user(self, email, password, **extra_fields):
        if not email:
            raise ValueError('Email is required')
        roles = extra_fields.pop('roles', None)
        user = self.model(email=self.normalize_email(email).lower(), **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        if roles:
            user.set_roles(roles)
        return user

    def create_user(self, email, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', False)
        extra_fields.setdefault('is_superuser', False)
        return self._create_user(email, password, **extra_fields)

    def create_superuser(self, email, password=None, **extra_fields):
        # The Admin / Owner account holds both roles (decision 03).
        extra_fields.setdefault('roles', [Role.ADMIN, Role.OWNER])
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        if not extra_fields.get('is_staff'):
            raise ValueError('Superuser must have is_staff=True.')
        if not extra_fields.get('is_superuser'):
            raise ValueError('Superuser must have is_superuser=True.')
        return self._create_user(email, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    """Custom User: email login, full name, one or more roles.

    Django's Group/Permission RBAC remains available via PermissionsMixin;
    held roles are the coarse, domain-level gate used by the CPMS modules.
    """

    email = models.EmailField(unique=True, help_text='Required. Login identifier.')
    full_name = models.CharField(max_length=200)
    phone = models.CharField(max_length=32, blank=True)
    employee_no = models.CharField(
        max_length=32,
        blank=True,
        help_text='Firm-issued employee number.',
    )
    company = models.ForeignKey(
        'apps_company.Company',
        on_delete=models.PROTECT,
        related_name='users',
    )

    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(
        default=False,
        help_text='Grants access to the Django admin site.',
    )

    date_joined = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserManager()

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['full_name']

    class Meta:
        verbose_name = 'User'
        verbose_name_plural = 'Users'
        ordering = ('full_name', 'email')
        constraints = [
            # Uniqueness must be case-insensitive, matching the lower-case save.
            models.UniqueConstraint(Lower('email'), name='apps_users_email_ci_unique'),
        ]

    def __str__(self):
        return f'{self.full_name} <{self.email}>'

    def save(self, *args, **kwargs):
        # One canonical form so logging in cannot depend on how it was typed.
        self.email = str(self.email).strip().lower()
        super().save(*args, **kwargs)

    # --- Roles ---
    @property
    def roles(self):
        """Held role codes, in the canonical capability order."""
        from . import capabilities

        return capabilities.held_roles(self)

    def set_roles(self, roles):
        """Replace the held roles with `roles` (a user keeps at least one)."""
        from . import capabilities

        wanted = capabilities.clean_roles(roles)
        UserRole.objects.filter(user=self).exclude(role__in=wanted).delete()
        for role in wanted:
            UserRole.objects.get_or_create(user=self, role=role)

    def has_role(self, role):
        return role in self.roles

    @property
    def active_role(self):
        """The role this user acts as when no `X-Active-Role` header is sent."""
        from . import capabilities

        return capabilities.default_role(self)

    @property
    def is_admin(self):
        return self.has_role(Role.ADMIN)

    @property
    def is_project_manager(self):
        return self.has_role(Role.OWNER)

    @property
    def is_client(self):
        return self.has_role(Role.CLIENT)

    def can_approve_requisitions(self):
        """Only Admin and Project Manager (owner) may approve material requests."""
        return Role.ADMIN in self.roles or Role.OWNER in self.roles


class UserRole(models.Model):
    """One role held by one user (junction; mirrors `user_role.dart`)."""

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='user_roles')
    role = models.CharField(max_length=32, choices=Role.choices, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'User role'
        verbose_name_plural = 'User roles'
        ordering = ('user_id', 'role')
        constraints = [
            models.UniqueConstraint(fields=['user', 'role'], name='apps_users_user_role_unique'),
        ]

    def __str__(self):
        return f'{self.user_id}: {self.role}'


class AuditLog(models.Model):
    """Server-written record of a security-relevant change (mirrors `audit_log.dart`)."""

    user = models.ForeignKey(User, on_delete=models.PROTECT, related_name='audit_logs')
    action = models.CharField(max_length=64)
    entity = models.CharField(max_length=64)
    entity_id = models.PositiveBigIntegerField()
    details = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Audit log'
        verbose_name_plural = 'Audit log'
        ordering = ('-created_at', '-id')

    def __str__(self):
        return f'{self.action} {self.entity}#{self.entity_id}'


class Notification(models.Model):
    """In-app notification for one user (mirrors `app_notification.dart`)."""

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='notifications')
    type = models.CharField(max_length=64)
    message = models.TextField()
    link = models.CharField(max_length=255, null=True, blank=True)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Notification'
        verbose_name_plural = 'Notifications'
        ordering = ('-created_at', '-id')

    def __str__(self):
        return f'{self.type} → {self.user_id}'
