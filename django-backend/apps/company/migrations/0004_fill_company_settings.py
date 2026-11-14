"""Give every company its settings row, so reading settings never writes.

`CompanySettingsView.get` used to `get_or_create` the row — a write inside a GET
(review 1.2 minor 3). Seeding here keeps the read read-only and still returns a
row with a real `id`, which `company_settings.dart` parses non-null.

Reverse is a no-op: migration 0002 removes the table on rollback anyway.
"""

from django.db import migrations


def seed_settings(apps, schema_editor):
    Company = apps.get_model('apps_company', 'Company')
    CompanySettings = apps.get_model('apps_company', 'CompanySettings')
    for company in Company.objects.all():
        CompanySettings.objects.get_or_create(company=company)


class Migration(migrations.Migration):

    dependencies = [
        ('apps_company', '0003_fill_pcab_license_expiry'),
    ]

    operations = [
        migrations.RunPython(seed_settings, migrations.RunPython.noop),
    ]
