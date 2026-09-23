"""Project, site, contract, phase and milestone serializers."""

from rest_framework import serializers

from .models import Contract, Milestone, Project, ProjectPhase, Site


class SiteSerializer(serializers.ModelSerializer):
    project_count = serializers.IntegerField(source='projects.count', read_only=True)

    class Meta:
        model = Site
        fields = (
            'id', 'code', 'name', 'address', 'city', 'province',
            'status', 'notes', 'project_count', 'created_at', 'updated_at',
        )
        read_only_fields = ('id', 'created_at', 'updated_at')


class ContractSerializer(serializers.ModelSerializer):
    project_code = serializers.CharField(source='project.code', read_only=True)

    class Meta:
        model = Contract
        fields = (
            'id', 'project', 'project_code', 'contract_no', 'client_name',
            'client_contact', 'amount', 'retention_percent', 'signed_date',
            'completion_date', 'status', 'notes', 'created_at', 'updated_at',
        )
        read_only_fields = ('id', 'created_at', 'updated_at')

    def validate_retention_percent(self, value):
        if value > 100:
            raise serializers.ValidationError('Retention percent cannot exceed 100.')
        return value


class MilestoneSerializer(serializers.ModelSerializer):
    is_complete = serializers.BooleanField(read_only=True)
    is_late = serializers.BooleanField(read_only=True)

    class Meta:
        model = Milestone
        fields = (
            'id', 'project', 'phase', 'title', 'due_date', 'completed_date',
            'is_complete', 'is_late', 'notes', 'created_at', 'updated_at',
        )
        read_only_fields = ('id', 'created_at', 'updated_at')


class ProjectPhaseSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProjectPhase
        fields = (
            'id', 'project', 'name', 'sequence', 'status', 'planned_start',
            'planned_end', 'actual_start', 'actual_end', 'progress_percent',
            'notes', 'created_at', 'updated_at',
        )
        read_only_fields = ('id', 'created_at', 'updated_at')

    def validate_progress_percent(self, value):
        if value > 100:
            raise serializers.ValidationError('Progress cannot exceed 100%.')
        return value


class ProjectSerializer(serializers.ModelSerializer):
    site_name = serializers.CharField(source='site.name', read_only=True)
    manager_name = serializers.CharField(source='manager.full_name', read_only=True)
    is_overdue = serializers.BooleanField(read_only=True)
    phase_count = serializers.IntegerField(source='phases.count', read_only=True)

    class Meta:
        model = Project
        fields = (
            'id', 'code', 'name', 'site', 'site_name', 'manager', 'manager_name',
            'status', 'description', 'start_date', 'target_end_date',
            'actual_end_date', 'budget_amount', 'is_overdue', 'phase_count',
            'created_at', 'updated_at',
        )
        read_only_fields = ('id', 'created_at', 'updated_at')

    def validate(self, attrs):
        start = attrs.get('start_date', getattr(self.instance, 'start_date', None))
        target = attrs.get('target_end_date', getattr(self.instance, 'target_end_date', None))
        if start and target and target < start:
            raise serializers.ValidationError(
                {'target_end_date': 'Target end date cannot precede the start date.'}
            )
        return attrs


class ProjectDetailSerializer(ProjectSerializer):
    """Project with its nested timeline, phases and contracts."""

    phases = ProjectPhaseSerializer(many=True, read_only=True)
    milestones = MilestoneSerializer(many=True, read_only=True)
    contracts = ContractSerializer(many=True, read_only=True)

    class Meta(ProjectSerializer.Meta):
        fields = ProjectSerializer.Meta.fields + ('phases', 'milestones', 'contracts')