from django.contrib import admin

from .models import Collectible, CollectiblePayment, ExpenseLog, ProjectBudget


@admin.register(ProjectBudget)
class ProjectBudgetAdmin(admin.ModelAdmin):
    list_display = ('project', 'category', 'planned_amount', 'actual_amount', 'variance')
    list_filter = ('category', 'project')
    search_fields = ('project__code', 'project__name')
    autocomplete_fields = ('project',)

    @admin.display(description='Actual')
    def actual_amount(self, obj):
        return obj.actual_amount

    @admin.display(description='Variance')
    def variance(self, obj):
        return obj.variance


@admin.register(ExpenseLog)
class ExpenseLogAdmin(admin.ModelAdmin):
    list_display = (
        'incurred_on', 'project', 'category', 'description',
        'amount', 'status', 'supplier',
    )
    list_filter = ('status', 'category', 'project')
    search_fields = ('description', 'receipt_no', 'supplier', 'project__code')
    autocomplete_fields = ('project', 'budget', 'recorded_by', 'approved_by')
    date_hierarchy = 'incurred_on'
    readonly_fields = ('approved_at',)


class CollectiblePaymentInline(admin.TabularInline):
    model = CollectiblePayment
    extra = 0


@admin.register(Collectible)
class CollectibleAdmin(admin.ModelAdmin):
    list_display = (
        'reference_no', 'debtor_name', 'project', 'amount',
        'amount_paid', 'balance', 'due_date', 'status',
    )
    list_filter = ('status', 'project')
    search_fields = ('reference_no', 'debtor_name', 'pos_collectible_ref')
    autocomplete_fields = ('project', 'recorded_by')
    date_hierarchy = 'due_date'
    inlines = (CollectiblePaymentInline,)

    @admin.display(description='Balance')
    def balance(self, obj):
        return obj.balance


@admin.register(CollectiblePayment)
class CollectiblePaymentAdmin(admin.ModelAdmin):
    list_display = (
        'collectible', 'amount', 'paid_on', 'method',
        'reference_no', 'received_by',
    )
    list_filter = ('method', 'paid_on')
    search_fields = ('collectible__reference_no', 'reference_no')
    autocomplete_fields = ('collectible', 'received_by')
    date_hierarchy = 'paid_on'