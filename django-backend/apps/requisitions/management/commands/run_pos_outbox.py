"""`run_pos_outbox` — deliver queued POS work (task 3.1b).

    python manage.py run_pos_outbox --once          # one pass, then exit
    python manage.py run_pos_outbox                 # loop forever
    python manage.py run_pos_outbox --sleep 5       # loop with a short pause

The command is deliberately thin: `pos_worker.run_once()` owns every rule, and
this file only decides whether to run one pass or keep going. Nothing secret is
ever printed — job counts only (never a token, never a bearer).

A broken configuration (no service credentials, an unusable origin) is reported
once and then left alone: a worker must not spin on a store it can never reach.
Concretely, the loop **exits** with a `CommandError`, so run it under a supervisor
(systemd `Restart=always`, a container restart policy, …) that backs off, and fix
the settings before it comes back. `--once` is the form for cron/one-shot
delivery, where the exit code is the whole answer.
"""

import logging
import time

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import DatabaseError

from ...pos_client import PosConfigError
from ...pos_worker import run_once

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = 'Deliver queued POS imports, closes and status refreshes.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--once', action='store_true',
            help='Run a single pass and exit instead of looping.',
        )
        parser.add_argument(
            '--limit', type=int, default=None,
            help='Handle at most this many jobs in one pass.',
        )
        parser.add_argument(
            '--sleep', type=int,
            default=getattr(settings, 'POS_OUTBOX_POLL_SECONDS', 30),
            help='Seconds to wait between passes when looping.',
        )

    def handle(self, *args, **options):
        if options['once']:
            processed = self._pass(options['limit'])
            self.stdout.write(f'POS outbox: {processed} job(s) processed.')
            return

        pause = max(1, int(options['sleep']))
        self.stdout.write(f'POS outbox worker looping every {pause}s (Ctrl-C to stop).')
        while True:
            self._pass(options['limit'])
            time.sleep(pause)

    def _pass(self, limit):
        try:
            return run_once(limit=limit)
        except PosConfigError as problem:
            # No credentials or an unusable origin: retrying cannot fix it.
            raise CommandError(f'The POS bridge is misconfigured: {problem}') from problem
        except DatabaseError:
            # Another worker or a restart raced us; the jobs are still durable.
            logger.exception('POS outbox pass failed on the database; retrying later.')
            return 0
