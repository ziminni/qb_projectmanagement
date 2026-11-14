from django.contrib import admin

from .models import Company


@admin.register(Company)
class CompanyAdmin(admin.ModelAdmin):
    list_display = ('name', 'tin', 'pcab_license_no', 'pcab_license_expiry')
    search_fields = ('name', 'tin', 'pcab_license_no')
