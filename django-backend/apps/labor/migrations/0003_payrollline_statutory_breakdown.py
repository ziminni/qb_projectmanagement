from decimal import Decimal

import django.core.validators
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('apps_labor', '0002_payroll'),
    ]

    operations = [
        migrations.AddField(
            model_name='payrollline',
            name='sss',
            field=models.DecimalField(
                decimal_places=2,
                default=Decimal('0.00'),
                max_digits=12,
                validators=[django.core.validators.MinValueValidator(0)],
            ),
        ),
        migrations.AddField(
            model_name='payrollline',
            name='philhealth',
            field=models.DecimalField(
                decimal_places=2,
                default=Decimal('0.00'),
                max_digits=12,
                validators=[django.core.validators.MinValueValidator(0)],
            ),
        ),
        migrations.AddField(
            model_name='payrollline',
            name='pagibig',
            field=models.DecimalField(
                decimal_places=2,
                default=Decimal('0.00'),
                max_digits=12,
                validators=[django.core.validators.MinValueValidator(0)],
            ),
        ),
        migrations.AlterField(
            model_name='payrollline',
            name='deductions_policy',
            field=models.CharField(
                choices=[('unconfigured', 'Not configured'), ('configured', 'Configured')],
                default='configured',
                max_length=16,
            ),
        ),
    ]
