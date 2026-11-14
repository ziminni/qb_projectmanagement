from django.apps import AppConfig


class MasterDataConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.master_data'
    label = 'apps_master_data'
    verbose_name = 'Master Data (materials, suppliers, trades, equipment)'
