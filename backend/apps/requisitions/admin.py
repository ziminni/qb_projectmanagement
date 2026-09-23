from django.contrib import admin

from .models import (
    MaterialRequest,
    MaterialRequestItem,
    PosSyncLog,
    ReleaseToken,
)


class MaterialRequestItemInline(admin.TabularInline):
    model = MaterialRequestItem
    extra = 0


@admin.register(MaterialRequest)
class MaterialRequestAdmin(admin.ModelAdmin):
    list_display = (
        'request_no', 'project', 'site', 'requested_by',
        'status', 'priority', 'needed_date', 'created_at',
    )
    list_filter = ('status', 'priority', 'site')
    search_fields = ('request_no', 'project__code', 'purpose')
    autocomplete_fields = ('project', 'site', 'requested_by', 'reviewed_by')
    date_hierarchy = 'created_at'
    inlines = (MaterialRequestItemInline,)
    readonly_fields = ('reviewed_at',)


@admin.register(MaterialRequestItem)
class MaterialRequestItemAdmin(admin.ModelAdmin):
    list_display = (
        'material_request', 'item_sku', 'unit', 'quantity_requested',
        'quantity_approved', 'quantity_released', 'unit_cost',
    )
    search_fields = ('item_sku', 'material_request__request_no')
    autocomplete_fields = ('material_request',)


@admin.register(ReleaseToken)
class ReleaseTokenAdmin(admin.ModelAdmin):
    list_display = (
        'token', 'material_request', 'status', 'issued_by',
        'issued_at', 'expires_at', 'redeemed_at', 'pos_reference',
    )
    list_filter = ('status',)
    search_fields = ('token', 'material_request__request_no', 'pos_reference')
    autocomplete_fields = ('material_request', 'issued_by')
    readonly_fields = ('token', 'issued_at', 'redeemed_at')


@admin.register(PosSyncLog)
class PosSyncLogAdmin(admin.ModelAdmin):
    """Read-only: this is an audit trail."""

    list_display = (
        'created_at', 'method', 'endpoint', 'status_code',
        'success', 'duration_ms', 'material_request',
    )
    list_filter = ('success', 'method')
    search_fields = ('endpoint', 'error_message')
    date_hierarchy = 'created_at'

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False