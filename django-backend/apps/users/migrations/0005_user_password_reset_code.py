from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('apps_users', '0004_user_must_change_password'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='reset_code_hash',
            field=models.CharField(
                blank=True,
                default='',
                help_text='Hashed 6-digit password reset code.',
                max_length=128,
            ),
        ),
        migrations.AddField(
            model_name='user',
            name='reset_code_expires_at',
            field=models.DateTimeField(
                blank=True,
                help_text='Expiration timestamp for the active password reset code.',
                null=True,
            ),
        ),
    ]
