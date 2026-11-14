"""Give every company row a PCAB expiry date.

`Company.fromJson` parses `pcab_license_expiry` with the non-null
`JsonUtils.toDate` (`flutter/lib/data/models/company.dart:56`), so a null value
crashes the desktop. Rows that never had a date get the same placeholder the
mock seed uses (`repositories/mock_company_data.dart:15-22`) until a real
license date is entered in Settings — contract flag 3.

Reverse is a no-op: it cannot tell a placeholder from a real date.
"""

from datetime import date

from django.db import migrations

PLACEHOLDER_EXPIRY = date(2026, 12, 15)


def fill_expiry(apps, schema_editor):
    Company = apps.get_model('apps_company', 'Company')
    Company.objects.filter(pcab_license_expiry__isnull=True).update(
        pcab_license_expiry=PLACEHOLDER_EXPIRY,
    )


class Migration(migrations.Migration):

    dependencies = [
        ('apps_company', '0002_companysettings'),
    ]

    operations = [
        migrations.RunPython(fill_expiry, migrations.RunPython.noop),
    ]
