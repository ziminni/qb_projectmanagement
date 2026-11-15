from django.contrib import admin

from .models import EquipmentItem, MaterialItem, Supplier, Trade


@admin.register(MaterialItem)
class MaterialItemAdmin(admin.ModelAdmin):
    list_display = ('name', 'unit', 'default_unit_cost', 'store_sku', 'pos_code')
    search_fields = ('name', 'store_sku', 'pos_code')


@admin.register(Supplier)
class SupplierAdmin(admin.ModelAdmin):
    list_display = ('name', 'contact_person', 'phone', 'is_own_store', 'pos_payer_id')
    list_filter = ('is_own_store',)
    search_fields = ('name', 'contact_person', 'phone')


@admin.register(Trade)
class TradeAdmin(admin.ModelAdmin):
    list_display = ('name',)
    search_fields = ('name',)


@admin.register(EquipmentItem)
class EquipmentItemAdmin(admin.ModelAdmin):
    list_display = ('name', 'ownership', 'rate', 'rate_unit')
    list_filter = ('ownership', 'rate_unit')
    search_fields = ('name',)
