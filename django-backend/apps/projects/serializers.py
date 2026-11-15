"""Output serializers for the Phase 2 project wire contract.

These render exactly the Flutter shapes; writes are validated in
`apps/projects/services.py` because every refusal has to be the mock's exact
`{"detail": ...}` text. Redaction is per active role (passed in the context as
`role`): non-finance roles never receive peso keys, and every role receives the
server-computed category `weight` so progress matches across roles
(decision 06 #3).
"""

# Pyright here runs without django-stubs/DRF stubs: `Meta` reads as an override
# of ModelSerializer.Meta, and the mixin's `super()` / `self.context` are untyped.
# pyright: reportIncompatibleVariableOverride=false, reportAttributeAccessIssue=false, reportGeneralTypeIssues=false

from rest_framework import serializers

from ..users import capabilities
from ..users.models import Role
from .models import Category, Client, Project, ProjectAssignment, Site, Todo


def category_weights(project):
    """Progress weight per category id: budget share, else equal shares.

    Mirrors `computeProjectProgress` — budget weights only apply when **every**
    category of the project has a positive budget.
    """
    categories = list(project.categories.all())
    if not categories:
        return {}
    if all(category.budget is not None and category.budget > 0 for category in categories):
        total = sum(category.budget for category in categories)
        return {
            category.pk: float(category.budget / total) for category in categories
        }
    share = 1 / len(categories)
    return {category.pk: share for category in categories}


class FinanceRedactedSerializer(serializers.ModelSerializer):
    """Omit the listed peso keys unless the active role sees finance."""

    finance_fields: tuple[str, ...] = ()

    def to_representation(self, instance):
        data = super().to_representation(instance)
        role = self.context.get('role')
        if self.finance_fields and not capabilities.sees_finance(role):
            for field in self.finance_fields:
                data.pop(field, None)
        return data


class SiteSerializer(serializers.ModelSerializer):
    """Unchanged Phase 3 tenant (`sites/`); `site_inventory` and `requisitions` use it."""

    project_count = serializers.IntegerField(source='projects.count', read_only=True)

    class Meta:
        model = Site
        fields = (
            'id', 'code', 'name', 'address', 'city', 'province', 'status', 'notes',
            'project_count', 'created_at', 'updated_at',
        )
        read_only_fields = fields


class ClientSerializer(serializers.ModelSerializer):
    class Meta:
        model = Client
        fields = (
            'id', 'name', 'contact_person', 'email', 'phone', 'address',
            'user_id', 'created_at', 'updated_at',
        )
        read_only_fields = fields


class ProjectSerializer(FinanceRedactedSerializer):
    # A client sees their own contract terms; admin and site engineer do not.
    finance_fields = ('contract_amount', 'down_payment_pct', 'retention_pct')
    client_id = serializers.IntegerField(read_only=True)

    class Meta:
        model = Project
        fields = (
            'id', 'code', 'name', 'location', 'latitude', 'longitude',
            'client_id', 'contract_amount', 'down_payment_pct', 'retention_pct',
            'start_date', 'target_end_date', 'actual_end_date', 'status',
            'created_at', 'updated_at',
        )
        read_only_fields = fields

    def to_representation(self, instance):
        data = super().to_representation(instance)
        # The client's own contract terms are visible; only staff finance roles
        # and the client get them (decision 06 #2).
        role = self.context.get('role')
        if role == Role.CLIENT:
            for field in self.finance_fields:
                data[field] = str(getattr(instance, field))
        return data


class ProjectAssignmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProjectAssignment
        fields = (
            'id', 'project_id', 'user_id', 'role_on_project', 'response', 'note',
            'responded_at', 'created_at', 'updated_at',
        )
        read_only_fields = fields


class ProjectRequestSerializer(serializers.BaseSerializer):
    """`{project, assignment}` for a pending request (`repositories/project_repository.dart:6-11`)."""

    def to_representation(self, instance):
        return {
            'project': ProjectSerializer(
                instance.project, context=self.context,
            ).data,
            'assignment': ProjectAssignmentSerializer(instance).data,
        }


class CategorySerializer(FinanceRedactedSerializer):
    finance_fields = ('budget',)
    weight = serializers.SerializerMethodField()

    class Meta:
        model = Category
        fields = (
            'id', 'project_id', 'name', 'budget', 'weight', 'sort_order',
            'created_at', 'updated_at',
        )
        read_only_fields = fields

    def get_weight(self, category):
        return self.context.get('weights', {}).get(category.pk, 0.0)


class TodoSerializer(serializers.ModelSerializer):
    class Meta:
        model = Todo
        fields = (
            'id', 'category_id', 'title', 'start_date', 'end_date', 'is_done',
            'done_by', 'done_at', 'is_verified', 'verified_by', 'verified_at',
            'daily_report_id', 'created_at', 'updated_at',
        )
        read_only_fields = fields
