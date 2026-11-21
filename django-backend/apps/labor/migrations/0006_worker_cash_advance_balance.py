from decimal import Decimal

import django.core.validators
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('apps_labor', '0005_project_worker_request'),
    ]

    operations = [
        migrations.AddField(
            model_name='worker',
            name='cash_advance_balance',
            field=models.DecimalField(
                decimal_places=2,
                default=Decimal('0.00'),
                max_digits=12,
                validators=[
                    django.core.validators.MinValueValidator(Decimal('0.00')),
                ],
            ),
        ),
    ]
