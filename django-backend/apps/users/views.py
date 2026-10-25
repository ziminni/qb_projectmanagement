"""Users app views — authentication and staff management."""

from django.contrib.auth import logout as django_logout
from rest_framework import status, viewsets
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken

from .models import User
from .permissions import IsAdminOrReadOnly
from .serializers import LoginSerializer, RegisterSerializer, UserSerializer, issue_tokens


@api_view(['POST'])
@permission_classes([AllowAny])
def register_view(request):
    """Register a new firm user and return a JWT pair."""
    serializer = RegisterSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = serializer.save()
    return Response(
        {'user': UserSerializer(user).data, **issue_tokens(user)},
        status=status.HTTP_201_CREATED,
    )


@api_view(['POST'])
@permission_classes([AllowAny])
def login_view(request):
    """Exchange username/password for a JWT access + refresh pair."""
    serializer = LoginSerializer(data=request.data, context={'request': request})
    serializer.is_valid(raise_exception=True)
    user = serializer.validated_data['user']
    return Response({'user': UserSerializer(user).data, **issue_tokens(user)})


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
    django_logout(request)
    return Response({'detail': 'Logged out.'})


@api_view(['GET', 'PATCH'])
@permission_classes([IsAuthenticated])
def me_view(request):
    """Return (GET) or update (PATCH) the authenticated user's profile."""
    if request.method == 'PATCH':
        serializer = UserSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)
    return Response(UserSerializer(request.user).data)


class UserViewSet(viewsets.ModelViewSet):
    """Staff directory. Read for all authenticated users; writes for Admin."""

    queryset = User.objects.all().order_by('username')
    serializer_class = UserSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        role = self.request.query_params.get('role')
        if role:
            queryset = queryset.filter(role=role)
        is_active = self.request.query_params.get('is_active')
        if is_active is not None:
            queryset = queryset.filter(is_active=is_active.lower() in ('1', 'true', 'yes'))
        return queryset