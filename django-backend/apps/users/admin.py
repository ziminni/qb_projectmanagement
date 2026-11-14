from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.forms import BaseUserCreationForm, UserChangeForm

from .models import AuditLog, Notification, User, UserRole

# Pyright here runs without django-stubs, so form Meta overrides look incompatible.
# pyright: reportIncompatibleVariableOverride=false


class AdminUserCreationForm(BaseUserCreationForm):
    class Meta:
        model = User
        fields = ('email', 'full_name', 'company')


class AdminUserChangeForm(UserChangeForm):
    class Meta:
        model = User
        fields = '__all__'


class UserRoleInline(admin.TabularInline):
    model = UserRole
    extra = 0


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    """Admin for the CPMS user, exposing the held roles."""

    form = AdminUserChangeForm
    add_form = AdminUserCreationForm
    list_display = ('full_name', 'email', 'is_active', 'is_staff')
    list_filter = ('is_active', 'is_staff', 'is_superuser')
    search_fields = ('full_name', 'email', 'employee_no')
    ordering = ('full_name',)
    readonly_fields = ('date_joined', 'updated_at', 'last_login')
    inlines = (UserRoleInline,)

    fieldsets = (
        (None, {'fields': ('email', 'password')}),
        ('Personal info', {'fields': ('full_name', 'phone', 'employee_no', 'company')}),
        ('Permissions', {
            'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions'),
        }),
        ('Important dates', {'fields': ('last_login', 'date_joined', 'updated_at')}),
    )

    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('email', 'full_name', 'company', 'password1', 'password2'),
        }),
    )


@admin.register(UserRole)
class UserRoleAdmin(admin.ModelAdmin):
    list_display = ('user', 'role', 'created_at')
    list_filter = ('role',)
    search_fields = ('user__full_name', 'user__email')


@admin.register(AuditLog)
class AuditLogAdmin(admin.ModelAdmin):
    list_display = ('created_at', 'user', 'action', 'entity', 'entity_id')
    list_filter = ('action', 'entity')
    search_fields = ('user__email', 'action', 'entity')
    readonly_fields = ('user', 'action', 'entity', 'entity_id', 'details',
                       'created_at', 'updated_at')


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ('created_at', 'user', 'type', 'is_read')
    list_filter = ('type', 'is_read')
    search_fields = ('user__email', 'message')
