"""Run an automated database backup when due per SystemBackupSchedule."""

import gzip
import hashlib
import io
import uuid
from datetime import timedelta
from pathlib import Path

from django.conf import settings
from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.users.models import SystemBackupSchedule
from apps.users.system_views import _enforce_retention


class Command(BaseCommand):
    help = 'Creates a scheduled database snapshot if due.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--force',
            action='store_true',
            help='Create a backup even if the schedule interval has not elapsed.',
        )

    def handle(self, *args, **options):
        schedule, _ = SystemBackupSchedule.objects.get_or_create(pk=1)
        if not options['force']:
            if schedule.frequency == SystemBackupSchedule.Frequency.MANUAL:
                self.stdout.write('Schedule is manual only; skipping.')
                return
            if schedule.last_backup_at is not None:
                interval = (
                    timedelta(days=7)
                    if schedule.frequency == SystemBackupSchedule.Frequency.WEEKLY
                    else timedelta(days=1)
                )
                if timezone.now() - schedule.last_backup_at < interval:
                    self.stdout.write('Backup is not due yet; skipping.')
                    return

        root = Path(settings.MEDIA_ROOT) / 'backups'
        root.mkdir(parents=True, exist_ok=True)
        stamp = timezone.now().strftime('%Y%m%d_%H%M%S')
        backup_id = f'cpms_backup_{stamp}_{uuid.uuid4().hex[:6]}'
        archive_path = root / f'{backup_id}.json.gz'
        sidecar_path = root / f'{backup_id}.sha256'

        buf = io.StringIO()
        call_command(
            'dumpdata',
            exclude=['contenttypes', 'auth.permission'],
            natural_foreign=True,
            natural_primary=True,
            stdout=buf,
        )
        with gzip.open(archive_path, 'wt', encoding='utf-8') as gz:
            gz.write(buf.getvalue())

        digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
        sidecar_path.write_text(digest, encoding='utf-8')

        schedule.last_backup_at = timezone.now()
        schedule.save()
        _enforce_retention(schedule.retention_count)
        self.stdout.write(self.style.SUCCESS(f'Created scheduled backup {backup_id}'))
