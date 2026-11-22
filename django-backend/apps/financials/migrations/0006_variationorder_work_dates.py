from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('apps_financials', '0005_variationorder_attachments'),
    ]

    operations = [
        migrations.AddField(
            model_name='variationorder',
            name='work_start_date',
            field=models.DateField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='variationorder',
            name='work_end_date',
            field=models.DateField(blank=True, null=True),
        ),
    ]
