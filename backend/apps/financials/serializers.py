"""Financials serializers — budget vs actuals, expenses, and utang."""

from rest_framework import serializers

from .models import (
    Collectible,
    CollectiblePayment,
    ExpenseLog,
    ProjectBudget,
)


class ProjectBudgetSerializer(serializers.ModelSerializer):
    category_display = serializers.CharField(source='get_category_display', read_only=True)
    project_code = serializers.CharField(source='project.code', read_only=True)
    actual_amount = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    variance = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    utilization_percent = serializers.DecimalField(
        max_digits=7,
        decimal_places=2,
        read_only=True,
    )
    is_over_budget = serializers.BooleanField(read_only=True)

    class Meta:
        model = ProjectBudget
        fields = (
            'id', 'project', 'project_code', 'category', 'category_display',
            'planned_amount', 'actual_amount', 'variance', 'utilization_percent',
            'is_over_budget', 'notes', 'created_at', 'updated_at',
        )
        read_only_fields = ('id', 'created_at', 'updated_at')


class ExpenseLogSerializer(serializers.ModelSerializer):
    category_display = serializers.CharField(source='get_category_display', read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    project_code = serializers.CharField(source='project.code', read_only=True)
    recorded_by_name = serializers.CharField(source='recorded_by.full_name', read_only=True)

    class Meta:
        model = ExpenseLog
        fields = (
            'id', 'project', 'project_code', 'budget', 'category',
            'category_display', 'description', 'amount', 'incurred_on',
            'receipt_no', 'supplier', 'status', 'status_display',
            'recorded_by', 'recorded_by_name', 'approved_by', 'approved_at',
            'notes', 'created_at', 'updated_at',
        )
        read_only_fields = (
            'id', 'approved_by', 'approved_at', 'created_at', 'updated_at',
        )


class CollectiblePaymentSerializer(serializers.ModelSerializer):
    method_display = serializers.CharField(source='get_method_display', read_only=True)
    received_by_name = serializers.CharField(source='received_by.full_name', read_only=True)

    class Meta:
        model = CollectiblePayment
        fields = (
            'id', 'collectible', 'amount', 'paid_on', 'method',
            'method_display', 'reference_no', 'received_by',
            'received_by_name', 'notes', 'created_at',
        )
        read_only_fields = ('id', 'created_at')


class CollectibleSerializer(serializers.ModelSerializer):
    payments = CollectiblePaymentSerializer(many=True, read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    project_code = serializers.CharField(source='project.code', read_only=True)
    balance = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    is_overdue = serializers.BooleanField(read_only=True)

    class Meta:
        model = Collectible
        fields = (
            'id', 'reference_no', 'project', 'project_code', 'debtor_name',
            'debtor_contact', 'description', 'amount', 'amount_paid', 'balance',
            'due_date', 'status', 'status_display', 'is_overdue',
            'pos_collectible_ref', 'recorded_by', 'payments',
            'created_at', 'updated_at',
        )
        read_only_fields = ('id', 'amount_paid', 'created_at', 'updated_at')