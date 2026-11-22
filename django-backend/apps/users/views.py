"""Users app views — authentication, staff management, audit and notifications.

Security rules enforced here (Phase 1.1 contract):
    * no public registration — accounts are created by an admin only;
    * `auth/me/` PATCH only accepts `full_name` and `phone`;
    * login and password-reset-request are throttled;
    * login never reveals whether an email exists;
    * audit rows and notifications are written by the server, never posted.
"""

# Pyright here runs without django-stubs or DRF type stubs, so transaction.atomic()
# and validated_data are inferred loosely; `manage.py check` and the tests are the gate.
# pyright: reportGeneralTypeIssues=false, reportAttributeAccessIssue=false, reportArgumentType=false

from datetime import timedelta
import hashlib
import logging

from django.contrib.auth.hashers import check_password, make_password
from django.db import transaction
from django.http import Http404
from django.utils import timezone
from rest_framework import generics, status, viewsets
from rest_framework.decorators import (
    action,
    api_view,
    permission_classes,
    throttle_classes,
)
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken

from . import capabilities, services
from .models import AuditLog, Notification, Role, User, UserRole
from .permissions import IsAdmin, IsAdminOrReadOnly, IsStaffOrSelfRead
from .serializers import (
    AuditLogSerializer,
    MeUpdateSerializer,
    NotificationSerializer,
    UserRoleSerializer,
    UserSerializer,
    UserWriteSerializer,
    user_payload,
)
from .throttles import (
    AccountLoginRateThrottle,
    LoginRateThrottle,
    PasswordResetRateThrottle,
)

WRONG_CREDENTIALS = 'Incorrect email or password.'
DEACTIVATED = 'This account is deactivated. Contact your system admin.'
NO_ROLE = 'This account has no role yet. Contact your system admin.'

# A failed login for an unknown email has no user row to audit against
# (AuditLog.user is non-null), so it goes to the security log as a hashed email.
security_log = logging.getLogger('cpms.security')


def issue_tokens(user):
    """Return a SimpleJWT access/refresh pair for `user`."""
    refresh = RefreshToken.for_user(user)
    return {'access': str(refresh.access_token), 'refresh': str(refresh)}


def _update_action(user, roles_before, active_before):
    """Name the audit action after what the admin actually changed."""
    if user.roles != roles_before:
        return 'user_roles_changed'
    if user.is_active != active_before:
        return 'user_activated' if user.is_active else 'user_deactivated'
    return 'user_updated'


@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([LoginRateThrottle, AccountLoginRateThrottle])
def login_view(request):
    """Exchange email/password for a JWT pair plus the user's roles."""
    email = str(request.data.get('email') or '').strip().lower()
    password = request.data.get('password') or ''
    if not email or not password:
        return Response(
            {'detail': 'An email and a password are required.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    user = User.objects.filter(email__iexact=email).first()
    if user is None:
        # Spend the same hashing time as a real check; no account enumeration.
        User().set_password(password)
        security_log.warning(
            'login_failed unknown_email: email_sha256=%s ip=%s',
            hashlib.sha256(email.encode()).hexdigest(),
            request.META.get('REMOTE_ADDR'),
        )
        return Response({'detail': WRONG_CREDENTIALS}, status=status.HTTP_400_BAD_REQUEST)

    if not user.check_password(password):
        with transaction.atomic():
            services.record(user, 'login_failed', 'auth', user.pk,
                            {'reason': 'incorrect_password'})
        return Response({'detail': WRONG_CREDENTIALS}, status=status.HTTP_400_BAD_REQUEST)

    # Django's ModelBackend reports inactive accounts as bad credentials; the
    # contract wants a distinct message, so activity is checked here.
    if not user.is_active:
        with transaction.atomic():
            services.record(user, 'login_failed', 'auth', user.pk,
                            {'reason': 'inactive'})
        return Response({'detail': DEACTIVATED}, status=status.HTTP_403_FORBIDDEN)

    roles = user.roles
    if not roles:
        with transaction.atomic():
            services.record(user, 'login_failed', 'auth', user.pk,
                            {'reason': 'no_role'})
        return Response({'detail': NO_ROLE}, status=status.HTTP_403_FORBIDDEN)

    with transaction.atomic():
        services.record(user, 'login', 'auth', user.pk, {'roles': roles})
    return Response({
        **user_payload(user),
        **issue_tokens(user),
    })


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def logout_view(request):
    """Blacklist the supplied refresh token."""
    refresh = request.data.get('refresh')
    if not refresh:
        return Response(
            {'detail': 'A refresh token is required.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    try:
        RefreshToken(refresh).blacklist()
    except TokenError:
        # Already expired or blacklisted — the session is gone either way.
        pass
    return Response({'detail': 'Logged out.'})


@api_view(['GET', 'PATCH'])
@permission_classes([IsAuthenticated])
def me_view(request):
    """Return (GET) or update (PATCH) the authenticated user's own profile."""
    if request.method == 'PATCH':
        writable = {'full_name', 'phone'}
        rejected = sorted(set(request.data) - writable)
        if rejected:
            return Response(
                {'detail': 'These fields cannot be changed: '
                           f'{", ".join(rejected)}. Only full_name and phone are editable.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = MeUpdateSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            serializer.save()
            services.record(request.user, 'profile_updated', 'user', request.user.pk,
                            {'fields': sorted(request.data)})
    return Response(user_payload(request.user))


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def change_password_view(request):
    """Change your own password after proving you know the current one."""
    current = str(request.data.get('current_password') or '')
    new_password = str(request.data.get('new_password') or '')
    if not current or not new_password:
        return Response(
            {'detail': 'Both the current and the new password are required.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if not request.user.check_password(current):
        return Response(
            {'detail': 'Your current password is incorrect.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if new_password == current:
        return Response(
            {'detail': 'Choose a password different from the current one.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    problem = services.password_rules_error(new_password, request.user)
    if problem:
        return Response({'detail': problem}, status=status.HTTP_400_BAD_REQUEST)

    with transaction.atomic():
        request.user.set_password(new_password)
        request.user.must_change_password = False
        request.user.save(
            update_fields=['password', 'must_change_password', 'updated_at'],
        )
        services.record(request.user, 'password_changed', 'user', request.user.pk)
    return Response({'detail': 'Password changed.'})


@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([PasswordResetRateThrottle])
def password_reset_request_view(request):
    """Generate a 6-digit reset code.

    When an email provider is configured, emails the code to the user.
    When email is off, delivers the 6-digit code directly into the System
    Administrator's in-app notifications so resets work with zero SMTP setup.
    Always returns 204 when accepted (never reveals whether an account exists).
    """
    email = str(request.data.get('email') or '').strip().lower()
    email_enabled = services.is_email_configured()
    if email:
        user = User.objects.filter(email__iexact=email, is_active=True).first()
        if user is not None:
            code = services.generate_reset_code()
            admin_msg = (
                f'{user.full_name} ({user.email}) asked for a password reset.'
                if email_enabled
                else (
                    f'{user.full_name} ({user.email}) asked for a password reset. '
                    f'6-digit reset code (valid 15 min): {code}'
                )
            )
            with transaction.atomic():
                user.reset_code_hash = make_password(code)
                user.reset_code_expires_at = timezone.now() + timedelta(minutes=15)
                user.save(
                    update_fields=[
                        'reset_code_hash',
                        'reset_code_expires_at',
                        'updated_at',
                    ],
                )
                services.record(user, 'password_reset_requested', 'user', user.pk)
                services.notify_admins(
                    'password_reset_requested',
                    admin_msg,
                    link='/user-management',
                )
            if email_enabled:
                sent, err = services.send_password_reset_code_email(
                    user, code, expires_minutes=15,
                )
                if not sent:
                    # Fallback: still deliver the code to admins in-app so the
                    # user is never locked out even if an email relay hiccups.
                    services.notify_admins(
                        'password_reset_requested',
                        f'Email failed for {user.email} ({err}). '
                        f'6-digit reset code (valid 15 min): {code}',
                        link='/user-management',
                    )
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([PasswordResetRateThrottle])
def password_reset_confirm_view(request):
    """Verify the 6-digit reset code and replace the user's password."""
    email = str(request.data.get('email') or '').strip().lower()
    code = str(request.data.get('code') or '').strip()
    new_password = str(request.data.get('new_password') or '')

    if not email or not code or not new_password:
        return Response(
            {'detail': 'Email, reset code, and new password are required.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    invalid_response = Response(
        {'detail': 'Invalid or expired reset code.'},
        status=status.HTTP_400_BAD_REQUEST,
    )
    user = User.objects.filter(email__iexact=email, is_active=True).first()
    if (
        user is None
        or not user.reset_code_hash
        or user.reset_code_expires_at is None
        or user.reset_code_expires_at < timezone.now()
        or not check_password(code, user.reset_code_hash)
    ):
        return invalid_response

    problem = services.password_rules_error(new_password, user)
    if problem:
        return Response({'detail': problem}, status=status.HTTP_400_BAD_REQUEST)

    with transaction.atomic():
        user.set_password(new_password)
        user.must_change_password = False
        user.reset_code_hash = ''
        user.reset_code_expires_at = None
        user.save(
            update_fields=[
                'password',
                'must_change_password',
                'reset_code_hash',
                'reset_code_expires_at',
                'updated_at',
            ],
        )
        services.record(user, 'password_reset_completed', 'user', user.pk)

    return Response({'detail': 'Password reset successfully. You can now sign in.'})


class UserViewSet(viewsets.ModelViewSet):
    """Staff directory: reads for any staff role, writes and resets for Admin.

    There is no DELETE: accounts are deactivated, never removed.
    """

    serializer_class = UserSerializer
    permission_classes = [IsStaffOrSelfRead]
    http_method_names = ['get', 'post', 'put', 'patch', 'head', 'options']

    def get_queryset(self):
        queryset = User.objects.select_related('company').order_by('full_name', 'email')
        # A client sees only their own row; staff filter by role/activity.
        if capabilities.active_role(self.request) == Role.CLIENT:
            return queryset.filter(pk=self.request.user.pk)

        params = self.request.query_params
        role = params.get('role')
        if role:
            queryset = queryset.filter(user_roles__role=role).distinct()
        is_active = params.get('is_active')
        if is_active is not None:
            queryset = queryset.filter(is_active=is_active.lower() in ('1', 'true', 'yes'))
        return queryset

    def create(self, request, *args, **kwargs):
        serializer = UserWriteSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        password = services.generate_temporary_password()
        with transaction.atomic():
            user = serializer.save()
            user.set_password(password)
            user.must_change_password = True
            user.save(
                update_fields=['password', 'must_change_password', 'updated_at'],
            )
            services.record(request.user, 'user_created', 'user', user.pk,
                            {'roles': user.roles, 'is_active': user.is_active})
        email_sent, email_error = services.send_credentials_email(
            user, password, is_reset=False,
        )
        return Response(
            {
                **user_payload(user),
                'temporary_password': password,
                'email_sent': email_sent,
                'email_error': email_error,
            },
            status=status.HTTP_201_CREATED,
        )

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop('partial', False)
        user = self.get_object()
        roles_before = user.roles
        active_before = user.is_active
        serializer = UserWriteSerializer(
            user, data=request.data, partial=partial, context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            user = serializer.save()
            services.record(
                request.user,
                _update_action(user, roles_before, active_before),
                'user',
                user.pk,
                {'roles': user.roles, 'is_active': user.is_active},
            )
        return Response(user_payload(user))

    @action(detail=True, methods=['post'], permission_classes=[IsAdmin],
            url_path='reset-password')
    def reset_password(self, request, pk=None):
        """Admin action: replace the password with a generated temporary one."""
        user = self.get_object()
        password = services.generate_temporary_password()
        with transaction.atomic():
            user.set_password(password)
            user.must_change_password = True
            user.save(
                update_fields=['password', 'must_change_password', 'updated_at'],
            )
            services.record(request.user, 'password_reset', 'user', user.pk)
        email_sent, email_error = services.send_credentials_email(
            user, password, is_reset=True,
        )
        return Response({
            'temporary_password': password,
            'email_sent': email_sent,
            'email_error': email_error,
        })


class UserRoleListView(generics.ListAPIView):
    """Every role row, optionally `?user=<id>` (staff roles only)."""

    serializer_class = UserRoleSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = UserRole.objects.order_by('user_id', 'role')
        user_id = self.request.query_params.get('user')
        if user_id:
            queryset = queryset.filter(user_id=user_id)
        return queryset


class AuditLogListView(generics.ListAPIView):
    """Admin-only audit trail, newest first, `?entity=&entity_id=` filterable."""

    serializer_class = AuditLogSerializer
    permission_classes = [IsAdmin]

    def get_queryset(self):
        queryset = AuditLog.objects.order_by('-created_at', '-id')
        user_id = self.request.query_params.get('user')
        if user_id:
            queryset = queryset.filter(user_id=user_id)
        entity = self.request.query_params.get('entity')
        if entity:
            queryset = queryset.filter(entity=entity)
        entity_id = self.request.query_params.get('entity_id')
        if entity_id:
            queryset = queryset.filter(entity_id=entity_id)
        return queryset


class NotificationListView(generics.ListAPIView):
    """The caller's own notifications, newest first."""

    serializer_class = NotificationSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Notification.objects.filter(user=self.request.user).order_by(
            '-created_at', '-id',
        )


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def notification_read_view(request, pk):
    """Mark one of your own notifications as read (someone else's is a 404)."""
    notification = Notification.objects.filter(pk=pk, user=request.user).first()
    if notification is None:
        raise Http404
    if not notification.is_read:
        notification.is_read = True
        notification.save(update_fields=['is_read', 'updated_at'])
    return Response(NotificationSerializer(notification).data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def notifications_read_all_view(request):
    """Mark every notification of the caller as read."""
    updated = Notification.objects.filter(user=request.user, is_read=False).update(
        is_read=True,
    )
    return Response({'detail': f'{updated} notification(s) marked as read.'})
