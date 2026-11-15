"""User, role, audit and notification serializers.

Shapes mirror the Flutter models in `flutter/lib/data/models/` exactly; the
client is never reshaped to fit the backend.
"""

from rest_framework import serializers

from .models import AuditLog, Notification, Role, User, UserRole


class UserSerializer(serializers.ModelSerializer):
    """Read representation of a CPMS user (never password/staff flags)."""

    company_id = serializers.IntegerField(read_only=True)
    created_at = serializers.DateTimeField(source='date_joined', read_only=True)

    class Meta:
        model = User
        fields = (
            'id',
            'company_id',
            'full_name',
            'email',
            'phone',
            'is_active',
            'created_at',
            'updated_at',
        )
        read_only_fields = fields


class UserRoleSerializer(serializers.ModelSerializer):
    """One held role row (`user_role.dart`)."""

    user_id = serializers.IntegerField(read_only=True)

    class Meta:
        model = UserRole
        fields = ('id', 'user_id', 'role', 'created_at', 'updated_at')
        read_only_fields = fields


class AuditLogSerializer(serializers.ModelSerializer):
    """Audit row (`audit_log.dart`). Written by the server only."""

    user_id = serializers.IntegerField(read_only=True)

    class Meta:
        model = AuditLog
        fields = ('id', 'user_id', 'action', 'entity', 'entity_id', 'details',
                  'created_at', 'updated_at')
        read_only_fields = fields


class NotificationSerializer(serializers.ModelSerializer):
    """Notification row (`app_notification.dart`). Created by the server only."""

    user_id = serializers.IntegerField(read_only=True)

    class Meta:
        model = Notification
        fields = ('id', 'user_id', 'type', 'message', 'link', 'is_read',
                  'created_at', 'updated_at')
        read_only_fields = fields


class _NoPhoneIsBlank(serializers.CharField):
    """`phone`: the app sends null for an empty box; store it as no phone."""

    def __init__(self, **kwargs):
        super().__init__(max_length=32, allow_blank=True, allow_null=True, required=False, **kwargs)

    def validate_empty_values(self, data):
        if data is None:
            return (True, '')
        return super().validate_empty_values(data)


class MeUpdateSerializer(serializers.ModelSerializer):
    """The only two fields a user may change on their own profile."""

    full_name = serializers.CharField(max_length=200)
    phone = _NoPhoneIsBlank()

    class Meta:
        model = User
        fields = ('full_name', 'phone')


class UserWriteSerializer(serializers.ModelSerializer):
    """Admin create/update of a user; `roles` replaces the whole role set."""

    roles = serializers.ListField(
        child=serializers.ChoiceField(choices=Role.choices),
        allow_empty=False,
        write_only=True,
    )
    phone = _NoPhoneIsBlank()

    class Meta:
        model = User
        fields = ('full_name', 'email', 'phone', 'is_active', 'roles')

    def validate_email(self, value):
        email = value.strip().lower()
        clash = User.objects.filter(email__iexact=email)
        if self.instance is not None:
            clash = clash.exclude(pk=self.instance.pk)
        if clash.exists():
            raise serializers.ValidationError('Another user already has this email.')
        return email

    def validate_full_name(self, value):
        if not value.strip():
            raise serializers.ValidationError("Enter the user's full name.")
        return value.strip()

    def validate(self, attrs):
        self._check_lock_out_guards(attrs)
        return attrs

    def _check_lock_out_guards(self, attrs):
        """Never let the acting admin, or the last admin, lock the firm out."""
        user = self.instance
        if user is None or not user.is_active or not user.is_admin:
            return

        request = self.context.get('request')
        actor = getattr(request, 'user', None)
        new_roles = attrs.get('roles')
        loses_admin = new_roles is not None and Role.ADMIN not in new_roles
        deactivated = attrs.get('is_active') is False
        if not loses_admin and not deactivated:
            return

        if actor is not None and actor.pk == user.pk:
            detail = ('You cannot remove your own admin role.'
                      if loses_admin else 'You cannot deactivate your own account.')
            raise serializers.ValidationError({'detail': detail})

        other_admins = User.objects.filter(
            is_active=True, user_roles__role=Role.ADMIN,
        ).exclude(pk=user.pk).distinct()
        if not other_admins.exists():
            raise serializers.ValidationError({
                'detail': 'The last active admin cannot lose the admin role '
                          'or be deactivated.',
            })

    def create(self, validated_data):
        roles = validated_data.pop('roles')
        user = User(**validated_data)
        user.company = self.context['request'].user.company
        # The view sets the generated temporary password straight after.
        user.set_unusable_password()
        user.save()
        user.set_roles(roles)
        return user

    def update(self, instance, validated_data):
        roles = validated_data.pop('roles', None)
        for field, value in validated_data.items():
            setattr(instance, field, value)
        instance.save()
        if roles is not None:
            instance.set_roles(roles)
        return instance


def user_payload(user):
    """`{user, roles}` — the shape every auth/user endpoint returns."""
    return {'user': UserSerializer(user).data, 'roles': user.roles}
