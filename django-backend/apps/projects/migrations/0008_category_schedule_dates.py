from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('apps_projects', '0007_planned_material'),
    ]

    operations = [
        migrations.AddField(
            model_name='category',
            name='planned_weeks',
            field=models.CharField(
                blank=True,
                default='',
                help_text='Starting week or week range, e.g. "Week 1" or "2-3".',
                max_length=32,
            ),
        ),
        migrations.AddField(
            model_name='category',
            name='planned_days',
            field=models.PositiveIntegerField(
                blank=True,
                help_text='Duration of this item of work in calendar days.',
                null=True,
            ),
        ),
        migrations.AddField(
            model_name='category',
            name='start_date',
            field=models.DateField(
                blank=True,
                help_text='Planned start date of this item of work (drives the Gantt bar before to-dos exist).',
                null=True,
            ),
        ),
        migrations.AddField(
            model_name='category',
            name='end_date',
            field=models.DateField(
                blank=True,
                help_text='Planned end date of this item of work.',
                null=True,
            ),
        ),
    ]
