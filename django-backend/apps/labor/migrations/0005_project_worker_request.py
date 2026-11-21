from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('apps_labor', '0004_worker_address_phone'),
        ('apps_projects', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='ProjectWorkerRequest',
            fields=[
                (
                    'id',
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name='ID',
                    ),
                ),
                ('full_name', models.CharField(max_length=200)),
                ('address', models.CharField(max_length=255)),
                ('phone', models.CharField(max_length=32)),
                (
                    'status',
                    models.CharField(
                        choices=[
                            ('pending', 'Pending'),
                            ('approved', 'Approved'),
                            ('rejected', 'Rejected'),
                        ],
                        db_index=True,
                        default='pending',
                        max_length=16,
                    ),
                ),
                (
                    'rejection_reason',
                    models.CharField(blank=True, max_length=255, null=True),
                ),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                (
                    'project',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name='worker_requests',
                        to='apps_projects.project',
                    ),
                ),
                (
                    'requested_by',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name='+',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    'reviewed_by',
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name='+',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    'worker',
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name='project_requests',
                        to='apps_labor.worker',
                    ),
                ),
            ],
            options={
                'verbose_name': 'Project Worker Request',
                'verbose_name_plural': 'Project Worker Requests',
                'ordering': ('-created_at', '-id'),
            },
        ),
        migrations.AddIndex(
            model_name='projectworkerrequest',
            index=models.Index(
                fields=['project', 'status'],
                name='apps_labor__project_req_status_idx',
            ),
        ),
    ]
