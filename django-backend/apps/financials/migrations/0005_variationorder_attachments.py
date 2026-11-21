from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('apps_financials', '0004_billing_foundation'),
    ]

    operations = [
        migrations.AddField(
            model_name='variationorder',
            name='primary_attachments',
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AddField(
            model_name='variationorder',
            name='secondary_attachments',
            field=models.JSONField(blank=True, default=list),
        ),
    ]
