from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('apps_labor', '0003_payrollline_statutory_breakdown'),
    ]

    operations = [
        migrations.AddField(
            model_name='worker',
            name='address',
            field=models.CharField(blank=True, max_length=255, null=True),
        ),
        migrations.AddField(
            model_name='worker',
            name='phone',
            field=models.CharField(blank=True, max_length=32, null=True),
        ),
    ]
