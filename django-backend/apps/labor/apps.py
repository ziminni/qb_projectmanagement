from django.apps import AppConfig


class LaborConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.labor'
    label = 'apps_labor'
    verbose_name = 'Labor (workers and attendance)'
