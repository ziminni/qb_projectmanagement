"""Master-data views: materials, suppliers, trades, equipment.

Writes are audited by the server inside the same transaction as the change
(`apps.users.services.record`); the desktop's own `AdminAudit.record()` calls
become duplicates once task 1.3/2.3 swap the repositories.

Materials, suppliers and equipment have no delete in `MasterDataRepository`, so
their routes answer 405 on `DELETE`. A trade is deleted for real (the mock does,
`mock_master_data_repository.dart:86-88`) — see the contract's flagged risk 2.
"""

# Pyright here runs without django-stubs or DRF type stubs, so validated_data and
# transaction.atomic() are inferred loosely; `manage.py check` and the tests gate.
# pyright: reportGeneralTypeIssues=false, reportAttributeAccessIssue=false, reportArgumentType=false

from django.db import IntegrityError, transaction
from django.db.models.deletion import ProtectedError
from rest_framework import mixins, status, viewsets
from rest_framework.response import Response

from ..users import services
from .models import EquipmentItem, MaterialItem, Supplier, Trade
from .permissions import IsMasterDataWriter
from .serializers import (
    EquipmentItemSerializer,
    MaterialItemSerializer,
    SupplierSerializer,
    TradeSerializer,
    refusal,
)


class AuditedMasterDataViewSet(viewsets.GenericViewSet):
    """Read/create/update a master list, writing one audit row per change.

    `entity` is the audit entity name, matching what the desktop records today
    (`material`, `supplier`, `trade`, `equipment`).
    """

    permission_classes = [IsMasterDataWriter]
    entity = ''

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        if not serializer.is_valid():
            return Response(refusal(serializer), status=status.HTTP_400_BAD_REQUEST)
        instance, error = self.save_and_audit(request, serializer,
                                              f'{self.entity}_created')
        if error is not None:
            return error
        return Response(self.get_serializer(instance).data,
                        status=status.HTTP_201_CREATED)

    def update(self, request, *args, **kwargs):
        instance = self.get_object()
        serializer = self.get_serializer(instance, data=request.data,
                                        partial=kwargs.get('partial', False))
        if not serializer.is_valid():
            return Response(refusal(serializer), status=status.HTTP_400_BAD_REQUEST)
        instance, error = self.save_and_audit(request, serializer,
                                              f'{self.entity}_updated')
        if error is not None:
            return error
        return Response(self.get_serializer(instance).data)

    def save_and_audit(self, request, serializer, action):
        """Save and audit in one transaction; return `(instance, error_response)`.

        A duplicate name can slip past the serializer's pre-check when two
        requests race (review 1.2 minor 2). The unique index answers instead, so
        the `IntegrityError` becomes the serializer's own refusal text. The
        atomic block is the savepoint that keeps the connection usable.
        """
        duplicate_message = getattr(serializer, 'duplicate_name_message', None)
        try:
            with transaction.atomic():
                instance = serializer.save()
                services.record(request.user, action, self.entity, instance.pk,
                                {'name': str(instance)})
        except IntegrityError:
            if duplicate_message is None:
                raise
            return None, Response({'detail': duplicate_message},
                                  status=status.HTTP_400_BAD_REQUEST)
        return instance, None

    def partial_update(self, request, *args, **kwargs):
        kwargs['partial'] = True
        return self.update(request, *args, **kwargs)


class MaterialItemViewSet(
    AuditedMasterDataViewSet,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
):
    queryset = MaterialItem.objects.all()
    serializer_class = MaterialItemSerializer
    entity = 'material'


class SupplierViewSet(
    AuditedMasterDataViewSet,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
):
    queryset = Supplier.objects.all()
    serializer_class = SupplierSerializer
    entity = 'supplier'


class TradeViewSet(
    AuditedMasterDataViewSet,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.DestroyModelMixin,
):
    queryset = Trade.objects.all()
    serializer_class = TradeSerializer
    entity = 'trade'

    def destroy(self, request, *args, **kwargs):
        """Delete a trade, or refuse cleanly while a worker (or another FK) uses it.

        `Worker.trade` is a protected FK, so the `ProtectedError` is a `400`
        with a readable text — never a `500`. The audit row is inside the same
        atomic block as the delete, so a refused delete leaves no audit.
        """
        instance = self.get_object()
        try:
            with transaction.atomic():
                services.record(request.user, 'trade_deleted', self.entity,
                                instance.pk, {'name': str(instance)})
                instance.delete()
        except ProtectedError:
            return Response({'detail': 'This trade is used by workers and cannot be deleted.'},
                            status=status.HTTP_400_BAD_REQUEST)
        return Response(status=status.HTTP_204_NO_CONTENT)


class EquipmentItemViewSet(
    AuditedMasterDataViewSet,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
):
    queryset = EquipmentItem.objects.all()
    serializer_class = EquipmentItemSerializer
    entity = 'equipment'
