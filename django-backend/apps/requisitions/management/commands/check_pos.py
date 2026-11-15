# pyright: reportAttributeAccessIssue=false
"""`manage.py check_pos` — can CPMS use the store (POS) right now?

Signs in to the store the way the outbox worker does and checks the three
things an own-store order needs: the store answers, the own-store supplier's
payer is a contractor the store lists, and every mapped material code is one
the store sells. Prints a short checklist; exits non-zero with the first
problem so a demo can be checked before anyone places an order.

    docker compose exec backend python manage.py check_pos
"""

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from apps.master_data.models import MaterialItem, Supplier

from ...models import PosOutboxJob, PosOutboxState
from ...pos_client import PosError, get_pos_client


class Command(BaseCommand):
    help = 'Check that CPMS can reach the store (POS) and that its settings match.'

    def handle(self, *args, **options):
        say = self.stdout.write
        key_set = bool(getattr(settings, 'POS_API_GATEWAY_HEADER_VALUE', ''))
        say(f'Store address : {settings.POS_API_BASE_URL}')
        say(f'gateway key: {"set" if key_set else "not set (same-PC setup)"}')

        client = get_pos_client()
        try:
            customers = client.list_customers()
            materials = client.list_materials()
        except PosError as error:
            raise CommandError(
                f'Cannot use the store: {error} '
                'Check that POS is running, the tunnel URL is current and the '
                'gateway key matches (see README).'
            ) from error
        say(self.style.SUCCESS('Store answers and accepts the CPMS sign-in.'))

        names = {row.get('id'): row.get('name', '') for row in customers}
        payer = (
            Supplier.objects.filter(is_own_store=True)
            .values_list('pos_payer_id', flat=True).first()
        )
        if payer not in names:
            listed = ', '.join(f'{i} {n}' for i, n in names.items()) or 'none'
            raise CommandError(
                f'Own-store payer {payer} is not a contractor at the store '
                f'(store lists: {listed}). Restart the CPMS backend to relink it.'
            )
        say(self.style.SUCCESS(f'Bills the store contractor: {payer} {names[payer]}'))

        sold = {row.get('code') for row in materials}
        mapped = list(
            MaterialItem.objects.exclude(pos_code__isnull=True)
            .exclude(pos_code='').values_list('pos_code', flat=True)
        )
        missing = [code for code in mapped if code not in sold]
        if missing:
            raise CommandError(
                f'Material codes the store does not sell: {", ".join(missing)}. '
                'Fix them in Master lists > Materials.'
            )
        say(self.style.SUCCESS(
            f'Store sells {len(mapped)} of {len(mapped)} mapped materials.'
        ))

        waiting = PosOutboxJob.objects.filter(state=PosOutboxState.PENDING).count()
        failed = PosOutboxJob.objects.filter(state=PosOutboxState.FAILED).count()
        say(f'Outbox: {waiting} waiting, {failed} need review.')
        say(self.style.SUCCESS('READY: own-store orders can be sent.'))
