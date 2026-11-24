from decimal import Decimal
import django.core.validators
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('apps_master_data', '0001_initial'),
        ('apps_projects', '0006_todo_daily_report_fk'),
    ]

    operations = [
        migrations.AddField(
            model_name='category',
            name='item_no',
            field=models.CharField(
                blank=True,
                default='',
                help_text='Optional DPWH/BOQ item number, e.g. B.7(2) or 803(1)a.',
                max_length=32,
            ),
        ),
        migrations.AddField(
            model_name='category',
            name='labor_budget',
            field=models.DecimalField(
                blank=True,
                decimal_places=2,
                help_text='Optional DUPA Section A planned labor cost.',
                max_digits=14,
                null=True,
                validators=[django.core.validators.MinValueValidator(Decimal('0.00'))],
            ),
        ),
        migrations.AddField(
            model_name='category',
            name='equipment_budget',
            field=models.DecimalField(
                blank=True,
                decimal_places=2,
                help_text='Optional DUPA Section B planned equipment cost.',
                max_digits=14,
                null=True,
                validators=[django.core.validators.MinValueValidator(Decimal('0.00'))],
            ),
        ),
        migrations.AddField(
            model_name='category',
            name='material_budget',
            field=models.DecimalField(
                blank=True,
                decimal_places=2,
                help_text='Optional DUPA Section C planned material cost.',
                max_digits=14,
                null=True,
                validators=[django.core.validators.MinValueValidator(Decimal('0.00'))],
            ),
        ),
        migrations.CreateModel(
            name='PlannedMaterial',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=255)),
                ('unit', models.CharField(default='pcs', max_length=32)),
                ('planned_qty', models.DecimalField(decimal_places=2, max_digits=12, validators=[django.core.validators.MinValueValidator(Decimal('0.01'))])),
                ('unit_cost', models.DecimalField(decimal_places=2, default=Decimal('0.00'), max_digits=12, validators=[django.core.validators.MinValueValidator(Decimal('0.00'))])),
                ('sort_order', models.PositiveIntegerField(default=1)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('category', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='planned_materials', to='apps_projects.category')),
                ('material_item', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='planned_usages', to='apps_master_data.materialitem')),
                ('project', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='planned_materials', to='apps_projects.project')),
            ],
            options={
                'verbose_name': 'Planned Material',
                'verbose_name_plural': 'Planned Materials',
                'ordering': ('category__sort_order', 'sort_order', 'id'),
            },
        ),
        migrations.AddIndex(
            model_name='plannedmaterial',
            index=models.Index(fields=['project', 'category'], name='apps_projec_project_28a7b4_idx'),
        ),
    ]
