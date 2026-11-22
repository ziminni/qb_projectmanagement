from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('apps_users', '0003_systembackupschedule_systemsecuritypolicy'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='must_change_password',
            field=models.BooleanField(
                default=False,
                help_text='True until the user replaces their temporary password on first sign-in.',
            ),
        ),
    ]
