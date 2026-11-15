from django.db import migrations, models


def seed_company(apps, schema_editor):
    """The deployment serves one contractor company; seed its row."""
    Company = apps.get_model('apps_company', 'Company')
    Company.objects.get_or_create(name='BuildPro Construction Corporation')


class Migration(migrations.Migration):

    initial = True

    dependencies = []

    operations = [
        migrations.CreateModel(
            name='Company',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=200)),
                ('address', models.TextField(blank=True)),
                ('tin', models.CharField(blank=True, max_length=32, verbose_name='TIN')),
                ('pcab_license_no', models.CharField(blank=True, max_length=64, verbose_name='PCAB license no.')),
                ('pcab_license_expiry', models.DateField(blank=True, null=True)),
                ('logo_url', models.URLField(blank=True, max_length=500, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={
                'verbose_name': 'Company',
                'verbose_name_plural': 'Company',
            },
        ),
        migrations.RunPython(seed_company, migrations.RunPython.noop),
    ]
