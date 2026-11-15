"""`seed_demo` — load the dataset the Flutter app ships as its mocks (task 5.1).

    python manage.py seed_demo                      # needs DEBUG=on
    python manage.py seed_demo --i-know-this-is-demo # deliberate demo database
    python manage.py seed_demo --reset               # remove seed rows, then seed

The rows are the ones in `apps/users/demo_data.py`, which mirrors
`flutter/lib/data/repositories/mock_*.dart`.

Every write is an upsert keyed on a natural key (email, project code, material
name, …), so running it twice leaves the same rows — the command is safe to run
on every container start.

Two safety rules:

* it refuses to run unless `DEBUG` is on or `--i-know-this-is-demo` is passed,
  because it writes known demo passwords;
* `--reset` deletes **only** rows this command owns — the demo emails, project
  codes and master-list names above. Anything else in the database stays. The
  company row and its settings are updated, never deleted (users from other
  seeds depend on it through a PROTECT foreign key).

The password is never printed: the output names the accounts and points at the
documented demo password instead.
"""

from datetime import datetime, time, timedelta
from decimal import Decimal

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models import ProtectedError
from django.utils import timezone

from apps.company.models import Company, CompanySettings
from apps.labor.models import Attendance, AttendanceStatus, Worker
from apps.master_data.models import EquipmentItem, MaterialItem, Supplier, Trade
from apps.projects.models import (
    Category,
    Client,
    Project,
    ProjectAssignment,
    Todo,
)
from apps.users import demo_data
from apps.users.models import AuditLog, Notification, User

REQUIRED_FLAG = '--i-know-this-is-demo'
# The largest id `Supplier.pos_payer_id` (`PositiveBigIntegerField`) can store.
MAX_POS_PAYER_ID = 2**63 - 1


def _pos_payer_id(value):
    """`--pos-payer-id` as a POS customer id: a positive int the column can hold."""
    try:
        payer_id = int(value)
    except (TypeError, ValueError):
        raise CommandError(
            f'--pos-payer-id must be a whole number: the POS customer id from '
            f'GET integration/cpms/customers/ (got {value!r}).'
        ) from None
    if not 1 <= payer_id <= MAX_POS_PAYER_ID:
        raise CommandError(
            f'--pos-payer-id must be between 1 and {MAX_POS_PAYER_ID} (got {payer_id}).'
        )
    return payer_id


def _money(value):
    """A finite `Decimal` from a decimal string, never a float."""
    return Decimal(value).quantize(Decimal('0.01'))


def _at(day, hour):
    """An aware datetime for `hour` o'clock on `day` (mock's done/verified times)."""
    return timezone.make_aware(datetime.combine(day, time(hour)))


class Command(BaseCommand):
    help = (
        'Load the demo dataset that matches the Flutter mocks. '
        f'Refuses to run unless DEBUG is on or {REQUIRED_FLAG} is passed.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--reset',
            action='store_true',
            help='Delete the rows this command created before seeding again.',
        )
        parser.add_argument(
            '--i-know-this-is-demo',
            dest='demo_ack',
            action='store_true',
            help='Run against a database that is not in DEBUG mode.',
        )
        parser.add_argument(
            '--pos-payer-id',
            dest='pos_payer_id',
            type=_pos_payer_id,
            default=None,
            metavar='N',
            help=(
                'POS customer id the own-store supplier bills (read it from '
                'GET integration/cpms/customers/ in POS). Left unset it stays null '
                'and the output says so, because POS ids differ per database.'
            ),
        )
        parser.add_argument(
            '--auto-pos-payer',
            dest='auto_pos_payer',
            action='store_true',
            help=(
                'When --pos-payer-id is omitted and the own-store supplier has no '
                'payer yet, query POS GET integration/cpms/customers/ and pick '
                'the first customer automatically if POS is reachable.'
            ),
        )

    def handle(self, *args, **options):
        if not (settings.DEBUG or options['demo_ack']):
            raise CommandError(
                'Refusing to seed demo data: DEBUG is off, so this looks like a real '
                f'database. Re-run with {REQUIRED_FLAG} if it really is a demo one.'
            )

        pos_payer_id = options['pos_payer_id']
        if pos_payer_id is None and options.get('auto_pos_payer'):
            pos_payer_id = self._discover_pos_payer_id()

        # One transaction: a failed reset must not leave a half-seeded database.
        with transaction.atomic():
            if options['reset']:
                self._report_deleted(self._reset())
            counts = self._seed(pos_payer_id=pos_payer_id)

        self._report(counts)

    def _discover_pos_payer_id(self):
        """Best-effort POS contractor customer lookup when POS is already up."""
        if Supplier.objects.filter(
            is_own_store=True, pos_payer_id__isnull=False,
        ).exists():
            return None
        try:
            from apps.requisitions.pos_client import PosError, get_pos_client

            for row in get_pos_client().list_customers():
                if not isinstance(row, dict):
                    continue
                try:
                    candidate = int(row.get('id'))
                except (TypeError, ValueError):
                    continue
                if 1 <= candidate <= MAX_POS_PAYER_ID:
                    return candidate
        except (PosError, Exception):
            return None
        return None

    # ------------------------------------------------------------------ reset
    def _reset(self):
        """Delete only the rows this command owns. Returns the per-model counts."""
        users = User.objects.filter(email__in=[u['email'] for u in demo_data.USERS])
        projects = Project.objects.filter(code__in=[p['code'] for p in demo_data.PROJECTS])
        workers = Worker.objects.filter(
            full_name__in=[worker[0] for worker in demo_data.WORKERS],
        )
        # Trades are protected by workers, so workers go first.
        deleters = [
            Attendance.objects.filter(worker__in=workers),
            Attendance.objects.filter(project__in=projects),
            # Audit rows and notifications from demo logins belong to the demo.
            AuditLog.objects.filter(user__in=users),
            Notification.objects.filter(user__in=users),
            workers,
            # Cascades to assignments, categories and to-dos.
            projects,
            Client.objects.filter(name__in=[c['name'] for c in demo_data.CLIENTS]),
            MaterialItem.objects.filter(name__in=[m['name'] for m in demo_data.MATERIALS]),
            Supplier.objects.filter(name__in=[s['name'] for s in demo_data.SUPPLIERS]),
            Trade.objects.filter(name__in=demo_data.TRADES),
            EquipmentItem.objects.filter(name__in=[e['name'] for e in demo_data.EQUIPMENT]),
            users,
        ]
        deleted = {}
        try:
            for queryset in deleters:
                model = queryset.model.__name__
                total = deleted.get(model, 0) + queryset.delete()[0]
                deleted[model] = total
        except ProtectedError as error:
            raise CommandError(
                'Reset stopped: rows created after seeding still point at demo data '
                f'({error.args[1] if len(error.args) > 1 else error}). '
                'Nothing was deleted.'
            ) from error
        return deleted

    def _report_deleted(self, deleted):
        total = sum(deleted.values())
        self.stdout.write(f'Reset removed {total} seeded row(s): ' + ', '.join(
            f'{model} {count}' for model, count in sorted(deleted.items())
        ))

    # ------------------------------------------------------------------- seed
    def _seed(self, pos_payer_id=None):
        company = self._seed_company()
        users = self._seed_users(company)
        clients = self._seed_clients(users)
        self._seed_master_data(pos_payer_id)
        projects = self._seed_projects(clients)
        assignments = self._seed_assignments(projects, users)
        categories, todos = self._seed_wbs(projects, users)
        workers = self._seed_workers()
        attendance = self._seed_attendance(projects, workers, users)
        return {
            'company': company.name,
            'accounts': len(users),
            'own_store': Supplier.objects.filter(is_own_store=True).first(),
            'materials': MaterialItem.objects.filter(
                name__in=[m['name'] for m in demo_data.MATERIALS],
            ).count(),
            'pos_codes': MaterialItem.objects.exclude(pos_code__isnull=True).exclude(
                pos_code='',
            ).count(),
            'suppliers': Supplier.objects.filter(
                name__in=[s['name'] for s in demo_data.SUPPLIERS],
            ).count(),
            'trades': Trade.objects.filter(name__in=demo_data.TRADES).count(),
            'equipment': EquipmentItem.objects.filter(
                name__in=[e['name'] for e in demo_data.EQUIPMENT],
            ).count(),
            'projects': len(projects),
            'assignments': assignments,
            'categories': categories,
            'todos': todos,
            'workers': len(workers),
            'attendance': attendance,
        }

    def _seed_company(self):
        # One row per deployment: migration 0001 already creates it, so update
        # that row instead of adding a second company.
        company = Company.objects.order_by('pk').first()
        if company is None:
            company = Company(name=demo_data.COMPANY['name'])
        for field, value in demo_data.COMPANY.items():
            setattr(company, field, value)
        company.save()
        CompanySettings.objects.update_or_create(
            company=company,
            defaults={
                key: _money(value)
                for key, value in demo_data.COMPANY_SETTINGS.items()
            },
        )
        return company

    def _seed_users(self, company):
        users = {}
        for row in demo_data.USERS:
            user, _ = User.objects.get_or_create(
                email=row['email'],
                defaults={'full_name': row['full_name'], 'company': company},
            )
            user.full_name = row['full_name']
            user.phone = row['phone']
            user.company = company
            user.is_active = True
            # Re-applied on every run so a demo password that drifted is reset.
            user.set_password(demo_data.DEMO_PASSWORD)
            user.save()
            user.set_roles(row['roles'])
            users[row['email']] = user
        return users

    def _seed_clients(self, users):
        clients = {}
        for row in demo_data.CLIENTS:
            clients[row['name']], _ = Client.objects.update_or_create(
                name=row['name'],
                defaults={
                    'contact_person': row['contact_person'],
                    'email': row['email'],
                    'phone': row['phone'],
                    'address': row['address'],
                    'user': users.get(row['user']),
                },
            )
        return clients

    def _seed_master_data(self, pos_payer_id=None):
        for row in demo_data.MATERIALS:
            MaterialItem.objects.update_or_create(
                name=row['name'],
                defaults={
                    'unit': row['unit'],
                    'default_unit_cost': _money(row['default_unit_cost']),
                    'store_sku': row['store_sku'],
                    'pos_code': row['pos_code'],
                },
            )
        for row in demo_data.SUPPLIERS:
            defaults = {
                'contact_person': row['contact_person'],
                'phone': row['phone'],
                'address': row['address'],
                'is_own_store': row['is_own_store'],
            }
            if row['is_own_store'] and pos_payer_id is not None:
                # Only the own store bills a POS customer. Without the option the
                # stored value is left alone, so a re-seed cannot erase a payer an
                # operator already set through the API.
                defaults['pos_payer_id'] = pos_payer_id
            Supplier.objects.update_or_create(name=row['name'], defaults=defaults)
        for name in demo_data.TRADES:
            Trade.objects.update_or_create(name=name)
        for row in demo_data.EQUIPMENT:
            EquipmentItem.objects.update_or_create(
                name=row['name'],
                defaults={
                    'ownership': row['ownership'],
                    'rate': _money(row['rate']),
                    'rate_unit': row['rate_unit'],
                },
            )

    def _seed_projects(self, clients):
        projects = {}
        for row in demo_data.PROJECTS:
            projects[row['code']], _ = Project.objects.update_or_create(
                code=row['code'],
                defaults={
                    'name': row['name'],
                    'location': row['location'],
                    'latitude': Decimal(row['latitude']),
                    'longitude': Decimal(row['longitude']),
                    'client': clients[row['client']],
                    'contract_amount': _money(row['contract_amount']),
                    'down_payment_pct': _money(row['down_payment_pct']),
                    'retention_pct': _money(row['retention_pct']),
                    'start_date': row['start'],
                    'target_end_date': row['target_end'],
                    'status': row['status'],
                },
            )
        return projects

    def _seed_assignments(self, projects, users):
        for code, email, role, response in demo_data.ASSIGNMENTS:
            ProjectAssignment.objects.update_or_create(
                project=projects[code],
                user=users[email],
                role_on_project=role,
                defaults={
                    'response': response,
                    'responded_at': (
                        timezone.now() if response != 'not_sent' else None
                    ),
                },
            )
        return len(demo_data.ASSIGNMENTS)

    def _seed_wbs(self, projects, users):
        done_by = users[demo_data.TODO_CLOSED_BY]
        verified_by = users[demo_data.TODO_VERIFIED_BY]
        categories = todos = 0
        for code, rows in demo_data.CATEGORIES.items():
            by_name = {}
            for name, budget, sort_order in rows:
                by_name[name], _ = Category.objects.update_or_create(
                    project=projects[code],
                    name=name,
                    defaults={
                        'budget': _money(budget) if budget is not None else None,
                        'sort_order': sort_order,
                    },
                )
                categories += 1
        for code, rows in demo_data.TODOS.items():
            for category_name, title, start, end, state in rows:
                is_closed = state in ('done', 'verified')
                Todo.objects.update_or_create(
                    category=Category.objects.get(project=projects[code],
                                                   name=category_name),
                    title=title,
                    defaults={
                        'start_date': start,
                        'end_date': end,
                        'is_done': is_closed,
                        'done_by': done_by if is_closed else None,
                        'done_at': _at(end, 17) if is_closed else None,
                        'is_verified': state == 'verified',
                        'verified_by': verified_by if state == 'verified' else None,
                        'verified_at': (
                            _at(end + timedelta(days=1), 9)
                            if state == 'verified' else None
                        ),
                    },
                )
                todos += 1
        return categories, todos

    def _seed_workers(self):
        trades = {trade.name: trade for trade in Trade.objects.filter(
            name__in=demo_data.TRADES,
        )}
        workers = []
        for full_name, trade, rate, sss, philhealth, pagibig, is_active in (
            demo_data.WORKERS
        ):
            worker, _ = Worker.objects.update_or_create(
                full_name=full_name,
                defaults={
                    'trade': trades[trade],
                    'daily_rate': _money(rate),
                    'sss_no': sss,
                    'philhealth_no': philhealth,
                    'pagibig_no': pagibig,
                    'is_active': is_active,
                },
            )
            workers.append(worker)
        return workers

    def _seed_attendance(self, projects, workers, users):
        """The mocks' present/half-day pattern, for the first few working days."""
        seeded = 0
        day = demo_data.ATTENDANCE_FIRST_DAY
        working_days = 0
        while working_days < demo_data.ATTENDANCE_WORKING_DAYS:
            if day.weekday() == 6:  # the mock skips Sundays
                day += timedelta(days=1)
                continue
            working_days += 1
            for code, indexes, recorder in demo_data.ATTENDANCE_GROUPS:
                for index in indexes:
                    # The mock's own absences: every (day + worker) % 11 == 0.
                    absent = (day.day + index) % 11 == 0
                    Attendance.objects.update_or_create(
                        project=projects[code],
                        worker=workers[index - 1],
                        work_date=day,
                        defaults={
                            'status': (
                                AttendanceStatus.ABSENT if absent
                                else AttendanceStatus.PRESENT
                            ),
                            'overtime_hours': (
                                Decimal('2.00')
                                if not absent and day.weekday() == 5 and index <= 4
                                else Decimal('0.00')
                            ),
                            'recorded_by': users[recorder],
                        },
                    )
                    seeded += 1
            day += timedelta(days=1)
        return seeded

    # ----------------------------------------------------------------- report
    def _report(self, counts):
        self.stdout.write(self.style.SUCCESS('Demo data ready.'))
        self.stdout.write(f'  company: {counts["company"]}')
        self.stdout.write(
            '  accounts: ' + ', '.join(
                f'{row["email"]} ({"/".join(row["roles"])})'
                for row in demo_data.USERS
            )
        )
        self.stdout.write(
            f'  master lists: {counts["materials"]} materials '
            f'({counts["pos_codes"]} mapped to a POS code), '
            f'{counts["suppliers"]} suppliers, {counts["trades"]} trades, '
            f'{counts["equipment"]} equipment'
        )
        self.stdout.write(
            f'  projects: {counts["projects"]} '
            f'({counts["assignments"]} assignments, {counts["categories"]} categories, '
            f'{counts["todos"]} to-dos)'
        )
        self.stdout.write(
            f'  labor: {counts["workers"]} workers, {counts["attendance"]} attendance rows'
        )
        # A notice only: the password is documented, never echoed to a log.
        self.stdout.write(
            '  every account uses the documented demo password (not printed here).'
        )
        own_store = counts['own_store']
        if own_store is not None and own_store.pos_payer_id is None:
            # POS customer ids are not stable, so the seed cannot guess one: an
            # own-store PO cannot import until an operator names the real payer.
            self.stdout.write(
                '  own-store POS payer is not set: read the payer id from POS '
                'GET integration/cpms/customers/ and re-run with '
                'seed_demo --pos-payer-id N, or an own-store PO cannot import.'
            )
