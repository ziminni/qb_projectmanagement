from django.contrib import admin

from .models import Equipment, EquipmentLog, SiteStock, Tool


@admin.register(SiteStock)
class SiteStockAdmin(admin.ModelAdmin):
    list_display = (
        'item_sku', 'item_name', 'site', 'quantity_on_hand',
        'reorder_level', 'unit', 'condition',
    )
    list_filter = ('site', 'condition')
    search_fields = ('item_sku', 'item_name')
    autocomplete_fields = ('site',)


@admin.register(Tool)
class ToolAdmin(admin.ModelAdmin):
    list_display = (
        'code', 'name', 'site', 'quantity_total',
        'quantity_available', 'condition', 'custodian',
    )
    list_filter = ('site', 'condition')
    search_fields = ('code', 'name')
    autocomplete_fields = ('site', 'custodian')


class EquipmentLogInline(admin.TabularInline):
    model = EquipmentLog
    extra = 0
    readonly_fields = ('created_at',)


@admin.register(Equipment)
class EquipmentAdmin(admin.ModelAdmin):
    list_display = (
        'asset_code', 'name', 'category', 'site', 'status',
        'operator', 'maintenance_due',
    )
    list_filter = ('status', 'site', 'category')
    search_fields = ('asset_code', 'name')
    autocomplete_fields = ('site', 'operator')
    inlines = (EquipmentLogInline,)


@admin.register(EquipmentLog)
class EquipmentLogAdmin(admin.ModelAdmin):
    list_display = ('equipment', 'event_type', 'site', 'logged_by', 'occurred_at')
    list_filter = ('event_type', 'site')
    search_fields = ('equipment__asset_code', 'note')
    autocomplete_fields = ('equipment', 'site', 'logged_by')
    date_hierarchy = 'occurred_at'