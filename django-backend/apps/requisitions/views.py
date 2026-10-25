"""Requisitions app views — the CPMS ↔ POS material workflow."""

from django.utils import timezone
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..users.permissions import IsAdminOrReadOnly, IsProjectManagerOrAdmin
from .models import (
    MaterialRequest,
    MaterialRequestItem,
    PosSyncLog,
    ReleaseToken,
    RequestStatus,
    TokenStatus,
)
from .serializers import (
    ApproveRequestSerializer,
    MaterialRequestItemSerializer,
    MaterialRequestSerializer,
    PosSyncLogSerializer,
    RejectRequestSerializer,
    ReleaseTokenSerializer,
)
from .services import PosAPIError, get_pos_client, issue_release_token_for


class MaterialRequestViewSet(viewsets.ModelViewSet):
    """Field material requests, plus the approve/reject/release actions."""

    queryset = MaterialRequest.objects.select_related(
        'project', 'site', 'requested_by', 'reviewed_by',
    ).prefetch_related('items')
    serializer_class = MaterialRequestSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        status_param = params.get('status')
        if status_param:
            queryset = queryset.filter(status=status_param)

        priority = params.get('priority')
        if priority:
            queryset = queryset.filter(priority=priority)

        for field in ('project', 'site'):
            value = params.get(field)
            if value:
                queryset = queryset.filter(**{f'{field}_id': value})

        return queryset

    def perform_create(self, serializer):
        """Default the requester to the authenticated user."""
        if serializer.validated_data.get('requested_by'):
            serializer.save()
        else:
            serializer.save(requested_by=self.request.user)

    @action(detail=True, methods=['post'], permission_classes=[IsProjectManagerOrAdmin])
    def approve(self, request, pk=None):
        """Approve (or partially approve) the requisition."""
        material_request = self.get_object()
        serializer = ApproveRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        if material_request.status not in (
            RequestStatus.PENDING,
            RequestStatus.DRAFT,
            RequestStatus.PARTIALLY_APPROVED,
        ):
            return Response(
                {'detail': f'Cannot approve a request in status {material_request.status}.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        material_request.approve(
            user=request.user,
            partial=serializer.validated_data['partial'],
        )
        return Response(MaterialRequestSerializer(material_request).data)

    @action(detail=True, methods=['post'], permission_classes=[IsProjectManagerOrAdmin])
    def reject(self, request, pk=None):
        """Reject the requisition with an optional reason."""
        material_request = self.get_object()
        serializer = RejectRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        material_request.reject(
            user=request.user,
            reason=serializer.validated_data.get('reason', ''),
        )
        return Response(MaterialRequestSerializer(material_request).data)

    @action(detail=True, methods=['post'], permission_classes=[IsProjectManagerOrAdmin])
    def issue_token(self, request, pk=None):
        """Issue a digital release token and register it with the POS."""
        material_request = self.get_object()

        if material_request.status not in (
            RequestStatus.APPROVED,
            RequestStatus.PARTIALLY_APPROVED,
            RequestStatus.RELEASED,
        ):
            return Response(
                {'detail': 'The requisition must be approved before a release token is issued.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        token = issue_release_token_for(material_request, user=request.user)
        return Response(
            ReleaseTokenSerializer(token).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=['post'], permission_classes=[IsProjectManagerOrAdmin])
    def push_to_pos(self, request, pk=None):
        """Push this requisition to the POS backend."""
        material_request = self.get_object()
        items = [
            {
                'item_sku': item.item_sku,
                'quantity': str(item.quantity_approved or item.quantity_requested),
                'unit': item.unit,
                'unit_cost': str(item.unit_cost),
            }
            for item in material_request.items.all()
        ]
        try:
            response = get_pos_client().push_requisition(material_request, items)
        except PosAPIError as exc:
            return Response(
                {'detail': 'POS backend unavailable.', 'error': str(exc)},
                status=status.HTTP_502_BAD_GATEWAY,
            )
        return Response({'detail': 'Pushed to POS.', 'pos_response': response})


class MaterialRequestItemViewSet(viewsets.ModelViewSet):
    queryset = MaterialRequestItem.objects.select_related('material_request').all()
    serializer_class = MaterialRequestItemSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        request_id = self.request.query_params.get('material_request')
        if request_id:
            queryset = queryset.filter(material_request_id=request_id)
        return queryset


class ReleaseTokenViewSet(viewsets.ModelViewSet):
    """Digital release tokens handed to the hardware store for redemption."""

    queryset = ReleaseToken.objects.select_related(
        'material_request', 'issued_by',
    ).all()
    serializer_class = ReleaseTokenSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        token_status = params.get('status')
        if token_status:
            queryset = queryset.filter(status=token_status)

        request_id = params.get('material_request')
        if request_id:
            queryset = queryset.filter(material_request_id=request_id)

        return queryset

    @action(detail=True, methods=['post'], permission_classes=[IsProjectManagerOrAdmin])
    def revoke(self, request, pk=None):
        """Cancel a token that has not yet been redeemed."""
        token = self.get_object()
        if token.status == TokenStatus.REDEEMED:
            return Response(
                {'detail': 'A redeemed token cannot be revoked.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        token.revoke(reason=request.data.get('reason', ''))
        return Response(ReleaseTokenSerializer(token).data)

    @action(detail=False, methods=['post'], permission_classes=[IsAuthenticated])
    def redeem(self, request):
        """Redeem a token by its code (called by the POS during release).

        Deliberately NOT role-gated: the token itself is the authorization
        artifact — a single-use 128-bit secret with its own expiry — and the
        redeeming party is the POS service or the counter staff, not
        necessarily an Admin. Any authenticated caller is accepted, and every
        redemption is recorded against the token and the POS sync log.
        """
        code = request.data.get('token')
        if not code:
            return Response(
                {'detail': 'A token value is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        token = ReleaseToken.objects.filter(token=code).first()
        if token is None:
            return Response({'detail': 'Unknown token.'}, status=status.HTTP_404_NOT_FOUND)
        if not token.is_redeemable:
            return Response(
                {'detail': f'Token is not redeemable (status={token.status}).'},
                status=status.HTTP_409_CONFLICT,
            )

        token.mark_redeemed(
            pos_reference=request.data.get('pos_reference', ''),
            redeemed_by_name=request.data.get('redeemed_by_name', ''),
        )

        # Stamp the released quantities back onto the requisition lines.
        for item in token.material_request.items.all():
            item.quantity_released = item.quantity_approved
            item.save(update_fields=['quantity_released', 'updated_at'])

        material_request = token.material_request
        material_request.status = RequestStatus.RELEASED
        material_request.save(update_fields=['status', 'updated_at'])

        return Response(ReleaseTokenSerializer(token).data)


class PosSyncLogViewSet(viewsets.ReadOnlyModelViewSet):
    """Read-only audit trail of outbound POS calls."""

    queryset = PosSyncLog.objects.select_related('material_request', 'release_token').all()
    serializer_class = PosSyncLogSerializer
    permission_classes = [IsProjectManagerOrAdmin]

    def get_queryset(self):
        queryset = super().get_queryset()
        success = self.request.query_params.get('success')
        if success is not None:
            queryset = queryset.filter(success=success.lower() in ('1', 'true', 'yes'))
        return queryset