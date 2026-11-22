"""Send a live test email using the configured Django email settings.

Usage:
    python manage.py test_email recipient@example.com
"""

from django.conf import settings
from django.core.mail import send_mail
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = 'Send a test email to verify SMTP delivery.'

    def add_arguments(self, parser):
        parser.add_argument(
            'recipient',
            nargs='?',
            default=None,
            help='Recipient email address (defaults to EMAIL_HOST_USER).',
        )

    def handle(self, *args, **options):
        recipient = (options['recipient'] or settings.EMAIL_HOST_USER or '').strip()
        if not recipient:
            raise CommandError(
                'Provide a recipient email: python manage.py test_email you@example.com'
            )

        self.stdout.write(f'EMAIL_BACKEND:      {settings.EMAIL_BACKEND}')
        self.stdout.write(f'EMAIL_HOST:         {settings.EMAIL_HOST!r}')
        self.stdout.write(f'EMAIL_PORT:         {settings.EMAIL_PORT}')
        self.stdout.write(f'EMAIL_USE_TLS:      {settings.EMAIL_USE_TLS}')
        self.stdout.write(f'EMAIL_USE_SSL:      {settings.EMAIL_USE_SSL}')
        self.stdout.write(f'EMAIL_HOST_USER:    {settings.EMAIL_HOST_USER!r}')
        self.stdout.write(f'DEFAULT_FROM_EMAIL: {settings.DEFAULT_FROM_EMAIL!r}')

        if not settings.EMAIL_HOST:
            raise CommandError(
                'EMAIL_HOST is empty, so Django is using the console backend and '
                'will NOT send a real email. Add EMAIL_HOST=smtp.gmail.com (on its '
                'own line) to django-backend/.env and try again.'
            )

        sent = send_mail(
            subject='Queen Builders CPMS — SMTP Test Email',
            message=(
                'Hello!\n\n'
                'This is a test email from Queen Builders CPMS.\n'
                'If you received this, SMTP email delivery is working.\n\n'
                '— Queen Builders CPMS'
            ),
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[recipient],
            fail_silently=False,
        )
        if sent:
            self.stdout.write(
                self.style.SUCCESS(f'SUCCESS: Test email sent to {recipient}')
            )
        else:
            raise CommandError('send_mail returned 0 (no email sent).')
