from django.contrib import admin

from .models import Contract, Milestone, Project, ProjectPhase, Site


class ProjectPhaseInline(admin.TabularInline):
    model = ProjectPhase
    extra = 0


class MilestoneInline(admin.TabularInline):
    model = Milestone
    extra = 0


class ContractInline(admin.TabularInline):
    model = Contract
    extra = 0


@admin.register(Site)
class SiteAdmin(admin.ModelAdmin):
    list_display = ('code', 'name', 'city', 'province', 'status')
    list_filter = ('status', 'province')
    search_fields = ('code', 'name', 'city', 'province')
    ordering = ('code',)


@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = (
        'code', 'name', 'site', 'manager', 'status',
        'start_date', 'target_end_date', 'budget_amount',
    )
    list_filter = ('status', 'site')
    search_fields = ('code', 'name', 'site__name', 'site__code')
    autocomplete_fields = ('site',)
    date_hierarchy = 'start_date'
    inlines = (ProjectPhaseInline, MilestoneInline, ContractInline)


@admin.register(Contract)
class ContractAdmin(admin.ModelAdmin):
    list_display = (
        'contract_no', 'project', 'client_name', 'amount',
        'retention_percent', 'signed_date', 'status',
    )
    list_filter = ('status', 'signed_date')
    search_fields = ('contract_no', 'client_name', 'project__code')
    autocomplete_fields = ('project',)


@admin.register(ProjectPhase)
class ProjectPhaseAdmin(admin.ModelAdmin):
    list_display = ('project', 'sequence', 'name', 'status', 'progress_percent')
    list_filter = ('status', 'project')
    search_fields = ('name', 'project__code')
    autocomplete_fields = ('project',)


@admin.register(Milestone)
class MilestoneAdmin(admin.ModelAdmin):
    list_display = ('title', 'project', 'phase', 'due_date', 'completed_date')
    list_filter = ('project',)
    search_fields = ('title', 'project__code')
    autocomplete_fields = ('project', 'phase')
    date_hierarchy = 'due_date'