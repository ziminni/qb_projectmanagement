"""Phase 4 slice 4.2a: progress billings, client payments, VOs and retention.

Additive only: the legacy budget/expense/collectible tables are untouched.
Written by hand from `makemigrations --dry-run -v 3` output so the test
container (which runs as root) never leaves root-owned files in the tree.
"""

from decimal import Decimal

import django.core.validators
import django.db.models.deletion
import django.utils.timezone
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('apps_financials', '0003_initial'),
        ('apps_projects', '0006_todo_daily_report_fk'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='ProgressBilling',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('billing_no', models.PositiveIntegerField()),
                ('period_end', models.DateField()),
                ('pct_accomplished', models.DecimalField(decimal_places=6, max_digits=7)),
                ('gross_earned', models.DecimalField(decimal_places=2, max_digits=14)),
                ('less_previous', models.DecimalField(decimal_places=2, max_digits=14)),
                ('less_dp_recoupment', models.DecimalField(decimal_places=2, max_digits=14)),
                ('less_retention', models.DecimalField(decimal_places=2, max_digits=14)),
                ('net_due', models.DecimalField(decimal_places=2, max_digits=14)),
                ('status', models.CharField(choices=[('draft', 'Draft'), ('pending_client', 'Waiting for client'), ('disputed', 'Disputed'), ('approved', 'Approved by client'), ('paid', 'Paid'), ('rejected', 'Withdrawn')], db_index=True, default='draft', max_length=16)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('project', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='progress_billings', to='apps_projects.project')),
            ],
            options={
                'verbose_name': 'Progress Billing',
                'verbose_name_plural': 'Progress Billings',
                'ordering': ('-period_end', '-id'),
            },
        ),
        migrations.CreateModel(
            name='ClientPayment',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('amount', models.DecimalField(decimal_places=2, max_digits=14, validators=[django.core.validators.MinValueValidator(Decimal('0.01'))])),
                ('paid_on', models.DateField(default=django.utils.timezone.localdate)),
                ('method', models.CharField(choices=[('cash', 'Cash'), ('check', 'Check'), ('bank_transfer', 'Bank transfer'), ('e_wallet', 'GCash / e-wallet')], default='cash', max_length=16)),
                ('reference_no', models.CharField(blank=True, max_length=64)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('progress_billing', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='payments', to='apps_financials.progressbilling')),
            ],
            options={
                'verbose_name': 'Client Payment',
                'verbose_name_plural': 'Client Payments',
                'ordering': ('-paid_on', '-id'),
            },
        ),
        migrations.CreateModel(
            name='RetentionRelease',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('amount', models.DecimalField(decimal_places=2, max_digits=14, validators=[django.core.validators.MinValueValidator(Decimal('0.01'))])),
                ('released_on', models.DateField(default=django.utils.timezone.localdate)),
                ('method', models.CharField(choices=[('cash', 'Cash'), ('check', 'Check'), ('bank_transfer', 'Bank transfer'), ('e_wallet', 'GCash / e-wallet')], default='cash', max_length=16)),
                ('reference_no', models.CharField(blank=True, max_length=64)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('project', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='retention_releases', to='apps_projects.project')),
            ],
            options={
                'verbose_name': 'Retention Release',
                'verbose_name_plural': 'Retention Releases',
                'ordering': ('-released_on', '-id'),
            },
        ),
        migrations.CreateModel(
            name='VariationOrder',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('vo_no', models.CharField(max_length=16)),
                ('type', models.CharField(choices=[('additive', 'Added work'), ('deductive', 'Deleted work'), ('change', 'Design change')], max_length=16)),
                ('description', models.CharField(max_length=255)),
                ('amount', models.DecimalField(decimal_places=2, default=Decimal('0.00'), max_digits=14)),
                ('days_impact', models.IntegerField(default=0)),
                ('status', models.CharField(choices=[('proposed', 'Proposed'), ('pending_client', 'Waiting for client'), ('approved', 'Approved'), ('rejected', 'Rejected')], db_index=True, default='proposed', max_length=16)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('approved_by_client', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, related_name='+', to=settings.AUTH_USER_MODEL)),
                ('approved_by_owner', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, related_name='+', to=settings.AUTH_USER_MODEL)),
                ('project', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='variation_orders', to='apps_projects.project')),
            ],
            options={
                'verbose_name': 'Variation Order',
                'verbose_name_plural': 'Variation Orders',
                'ordering': ('-created_at', '-id'),
            },
        ),
        migrations.AddIndex(
            model_name='progressbilling',
            index=models.Index(fields=['project', 'status'], name='apps_financ_project_adb4a0_idx'),
        ),
        migrations.AddConstraint(
            model_name='progressbilling',
            constraint=models.UniqueConstraint(fields=('project', 'billing_no'), name='apps_financials_billing_unique_project_no'),
        ),
        migrations.AddConstraint(
            model_name='progressbilling',
            constraint=models.UniqueConstraint(condition=models.Q(('status__in', ('draft', 'pending_client', 'disputed', 'approved'))), fields=('project',), name='apps_financials_billing_one_in_progress'),
        ),
        migrations.AddConstraint(
            model_name='progressbilling',
            constraint=models.UniqueConstraint(condition=models.Q(('status', 'rejected'), _negated=True), fields=('project', 'period_end'), name='apps_financials_billing_unique_project_period'),
        ),
        migrations.AddIndex(
            model_name='clientpayment',
            index=models.Index(fields=['progress_billing', 'paid_on'], name='apps_financ_progres_1f04e0_idx'),
        ),
        migrations.AddConstraint(
            model_name='clientpayment',
            constraint=models.CheckConstraint(condition=models.Q(('amount__gt', 0)), name='apps_financials_client_payment_amount_positive'),
        ),
        migrations.AddConstraint(
            model_name='retentionrelease',
            constraint=models.CheckConstraint(condition=models.Q(('amount__gt', 0)), name='apps_financials_retention_release_amount_positive'),
        ),
        migrations.AddIndex(
            model_name='variationorder',
            index=models.Index(fields=['project', 'status'], name='apps_financ_project_05540a_idx'),
        ),
        migrations.AddConstraint(
            model_name='variationorder',
            constraint=models.UniqueConstraint(fields=('project', 'vo_no'), name='apps_financials_vo_unique_project_no'),
        ),
    ]
