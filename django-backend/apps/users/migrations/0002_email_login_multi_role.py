"""Email login + multi-role junction, audit log and notifications.

Data steps, in order:
    1. add `full_name` (and a temporarily nullable `company`);
    2. create `UserRole`, `AuditLog`, `Notification`;
    3. copy first/last name into `full_name`, point every user at the seeded
       company, and turn the single legacy `role` into `UserRole` rows;
    4. drop `username`, `first_name`, `last_name` and `role`, then make
       `full_name`/`company` required and add the case-insensitive email
       constraint.

Reverse only restores the schema: the legacy columns cannot be re-populated
from the role junction, so this migration is intentionally not data-reversible.
"""

from django.db import migrations, models
from django.db.models.functions import Lower

# Pyright here runs without django-stubs, so `models.deletion.*` (exactly what
# makemigrations emits) and field defaults are unreadable to it.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

LEGACY_ROLE_MAP = {
    'ADMIN': 'admin',
    'PROJECT_MANAGER': 'owner',
    'SITE_SUPERVISOR': 'site_engineer',
    'ENGINEER': 'site_engineer',
}


def forwards(apps, schema_editor):
    User = apps.get_model('apps_users', 'User')
    UserRole = apps.get_model('apps_users', 'UserRole')
    Company = apps.get_model('apps_company', 'Company')

    company = Company.objects.order_by('pk').first()
    if company is None:
        raise RuntimeError(
            'apps_company has no Company row; run the company seed migration first.'
        )

    for user in User.objects.all():
        name = f'{user.first_name or ""} {user.last_name or ""}'.strip()
        user.full_name = name or user.username or user.email
        user.company_id = company.pk
        user.save(update_fields=['full_name', 'company'])

        role = LEGACY_ROLE_MAP.get(user.role)
        if role:
            UserRole.objects.get_or_create(user=user, role=role)


class Migration(migrations.Migration):

    dependencies = [
        ('apps_company', '0001_initial'),
        ('apps_users', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='full_name',
            field=models.CharField(default='', max_length=200),
            preserve_default=False,
        ),
        migrations.AddField(
            model_name='user',
            name='company',
            field=models.ForeignKey(
                null=True,
                on_delete=models.deletion.PROTECT,
                related_name='users',
                to='apps_company.company',
            ),
        ),
        migrations.CreateModel(
            name='UserRole',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('role', models.CharField(choices=[('admin', 'Admin / Owner'), ('owner', 'Project Manager'), ('site_engineer', 'Site Engineer / Foreman'), ('accountant', 'Accountant'), ('client', 'Client')], db_index=True, max_length=32)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.ForeignKey(on_delete=models.deletion.CASCADE, related_name='user_roles', to='apps_users.user')),
            ],
            options={
                'verbose_name': 'User role',
                'verbose_name_plural': 'User roles',
                'ordering': ('user_id', 'role'),
            },
        ),
        migrations.CreateModel(
            name='Notification',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('type', models.CharField(max_length=64)),
                ('message', models.TextField()),
                ('link', models.CharField(blank=True, max_length=255, null=True)),
                ('is_read', models.BooleanField(default=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.ForeignKey(on_delete=models.deletion.CASCADE, related_name='notifications', to='apps_users.user')),
            ],
            options={
                'verbose_name': 'Notification',
                'verbose_name_plural': 'Notifications',
                'ordering': ('-created_at', '-id'),
            },
        ),
        migrations.CreateModel(
            name='AuditLog',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('action', models.CharField(max_length=64)),
                ('entity', models.CharField(max_length=64)),
                ('entity_id', models.PositiveBigIntegerField()),
                ('details', models.JSONField(blank=True, default=dict)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.ForeignKey(on_delete=models.deletion.PROTECT, related_name='audit_logs', to='apps_users.user')),
            ],
            options={
                'verbose_name': 'Audit log',
                'verbose_name_plural': 'Audit log',
                'ordering': ('-created_at', '-id'),
            },
        ),
        migrations.AddConstraint(
            model_name='userrole',
            constraint=models.UniqueConstraint(fields=('user', 'role'), name='apps_users_user_role_unique'),
        ),
        migrations.RunPython(forwards, migrations.RunPython.noop),
        migrations.RemoveField(model_name='user', name='username'),
        migrations.RemoveField(model_name='user', name='first_name'),
        migrations.RemoveField(model_name='user', name='last_name'),
        migrations.RemoveField(model_name='user', name='role'),
        migrations.AlterField(
            model_name='user',
            name='company',
            field=models.ForeignKey(
                on_delete=models.deletion.PROTECT,
                related_name='users',
                to='apps_company.company',
            ),
        ),
        migrations.AlterField(
            model_name='user',
            name='email',
            field=models.EmailField(help_text='Required. Login identifier.', max_length=254, unique=True),
        ),
        migrations.AlterModelOptions(
            name='user',
            options={
                'ordering': ('full_name', 'email'),
                'verbose_name': 'User',
                'verbose_name_plural': 'Users',
            },
        ),
        migrations.AddConstraint(
            model_name='user',
            constraint=models.UniqueConstraint(Lower('email'), name='apps_users_email_ci_unique'),
        ),
    ]
