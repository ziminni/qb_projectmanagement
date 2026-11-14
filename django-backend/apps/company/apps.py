from django.apps import AppConfig

# pyright: reportAssignmentType=false


class CompanyConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.company'
    label = 'apps_company'
    verbose_name = 'Company Profile'
