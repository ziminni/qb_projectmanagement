"""Financials app views — budgets, expenses and the utang ledger."""

from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from ..users.permissions import IsAdminOrReadOnly, IsProjectManagerOrAdmin
from .models import Collectible, CollectiblePayment, ExpenseLog, ProjectBudget
from .serializers import (
    CollectiblePaymentSerializer,
    CollectibleSerializer,
    ExpenseLogSerializer,
    ProjectBudgetSerializer,
)


class ProjectBudgetViewSet(viewsets.ModelViewSet):
    """Budget lines with derived actuals and variance."""

    queryset = ProjectBudget.objects.select_related('project').all()
    serializer_class = ProjectBudgetSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        project = params.get('project')
        if project:
            queryset = queryset.filter(project_id=project)

        category = params.get('category')
        if category:
            queryset = queryset.filter(category=category)

        return queryset


class ExpenseLogViewSet(viewsets.ModelViewSet):
    queryset = ExpenseLog.objects.select_related(
        'project', 'budget', 'recorded_by', 'approved_by',
    ).all()
    serializer_class = ExpenseLogSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        for field in ('project', 'category', 'status'):
            value = params.get(field)
            if value:
                key = 'project_id' if field == 'project' else field
                queryset = queryset.filter(**{key: value})

        return queryset

    def perform_create(self, serializer):
        if serializer.validated_data.get('recorded_by'):
            serializer.save()
        else:
            serializer.save(recorded_by=self.request.user)

    @action(detail=True, methods=['post'], permission_classes=[IsProjectManagerOrAdmin])
    def approve(self, request, pk=None):
        """Approve an expense so it counts against the budget's actuals."""
        expense = self.get_object()
        expense.approve(request.user)
        return Response(ExpenseLogSerializer(expense).data)


class CollectibleViewSet(viewsets.ModelViewSet):
    """Money owed to the firm (utang), with payment recording."""

    queryset = Collectible.objects.select_related('project', 'recorded_by').prefetch_related('payments')
    serializer_class = CollectibleSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        status_param = params.get('status')
        if status_param:
            queryset = queryset.filter(status=status_param)

        project = params.get('project')
        if project:
            queryset = queryset.filter(project_id=project)

        debtor = params.get('debtor')
        if debtor:
            queryset = queryset.filter(debtor_name__icontains=debtor)

        return queryset

    @action(detail=True, methods=['post'])
    def record_payment(self, request, pk=None):
        """Record a payment against this collectible and refresh its status."""
        collectible = self.get_object()

        payload = request.data.copy()
        payload['collectible'] = collectible.pk
        serializer = CollectiblePaymentSerializer(data=payload)
        serializer.is_valid(raise_exception=True)
        serializer.save(received_by=request.user)

        # CollectiblePayment.save() already recomputed the rollup; re-read
        # so the response reflects the fresh balance and status.
        collectible.refresh_from_db()
        return Response(
            CollectibleSerializer(collectible).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=False, methods=['get'])
    def summary(self, request):
        """Aggregate receivables position across all collectibles."""
        from django.db.models import Sum

        outstanding = self.get_queryset().exclude(status='PAID')
        totals = outstanding.aggregate(total=Sum('amount'), paid=Sum('amount_paid'))
        total_amount = totals['total'] or 0
        total_paid = totals['paid'] or 0

        return Response({
            'open_count': outstanding.count(),
            'total_amount': total_amount,
            'total_paid': total_paid,
            'total_balance': total_amount - total_paid,
            'overdue_count': sum(1 for obj in outstanding if obj.is_overdue),
        })


class CollectiblePaymentViewSet(viewsets.ModelViewSet):
    queryset = CollectiblePayment.objects.select_related('collectible', 'received_by').all()
    serializer_class = CollectiblePaymentSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        collectible = self.request.query_params.get('collectible')
        if collectible:
            queryset = queryset.filter(collectible_id=collectible)
        return queryset