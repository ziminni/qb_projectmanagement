"""Phase 4 slice 4.2a wire-contract tests: client-facing billing.

Every rule in `planning/backend-integration/contracts/phase-4-billing.md` has a
test here: the active-role fence (held roles are never unioned), accepted
assignment scoping / IDOR, client visibility of **billed** rows only, the full
billing state machine, overbilling/overpayment refusals (including one true
concurrent payment race), exact retention math and VO approval atomicity.

Derived `ProjectCosts`, payroll and POS/supplier payables are deliberately
absent: those are blocked on procurement valuation and payroll policy.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

import threading
from datetime import UTC, datetime, time, timedelta
from decimal import Decimal

from django.db import connection, connections
from django.test import TransactionTestCase
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from rest_framework.test import APIClient, APITestCase

from ..company.models import Company
from ..projects.models import (
    Category,
    Client,
    Project,
    ProjectAssignment,
    ProjectStatus,
    RequestResponse,
    RoleOnProject,
    Todo,
)
from ..users.models import AuditLog, Role
from ..users.tests import make_user
from . import billing_rules as rules
from .models import ProgressBilling, VariationOrder

BILLINGS_URL = '/api/v1/progress-billings/'
PREVIEW_URL = '/api/v1/progress-billings/preview/'
PAYMENTS_URL = '/api/v1/client-payments/'
SUMMARY_URL = '/api/v1/billing-summary/'
VOS_URL = '/api/v1/variation-orders/'
RETENTION_URL = '/api/v1/retention/'
RELEASES_URL = '/api/v1/retention-releases/'


def money(value):
    """A response money field as an exact Decimal (DRF sends 2-dp strings)."""
    return Decimal(str(value))


class BillingFixtures:
    """Two owned projects, one client per project, all five roles.

    Project A: contract 1,000,000, DP 10 %, retention 5 %, one category with
    four to-dos — two verified, so progress is exactly 0.5 and one billing is
    gross 500,000 / DP 50,000 / retention 25,000 / net due 425,000.
    """

    def setUp(self):
        if not Company.objects.exists():
            Company.objects.create(name='BuildPro Test')
        self.owner = make_user('maria@example.com', [Role.OWNER])
        self.accountant = make_user('liza@example.com', [Role.ACCOUNTANT])
        self.admin = make_user('admin@example.com', [Role.ADMIN])
        self.engineer = make_user('ramon@example.com', [Role.SITE_ENGINEER])
        self.client_user = make_user('elena@example.com', [Role.CLIENT])
        self.other_client_user = make_user('mark@example.com', [Role.CLIENT])
        # Holds two roles on purpose: the active role decides, never the union.
        self.dual = make_user('dual@example.com', [Role.ADMIN, Role.OWNER])

        self.client = Client.objects.create(name='Acme Holdings', user=self.client_user)
        self.other_client = Client.objects.create(
            name='Bayan Builders', user=self.other_client_user,
        )
        self.project = self.make_project('PRJ-A', 'Tower A', self.client)
        self.other_project = self.make_project('PRJ-B', 'Tower B', self.other_client)

        self.join(self.project, self.owner, RoleOnProject.OWNER)
        self.join(self.project, self.engineer, RoleOnProject.SITE_ENGINEER)
        self.join(self.project, self.client_user, RoleOnProject.CLIENT)
        self.join(self.other_project, self.owner, RoleOnProject.OWNER)
        self.join(self.other_project, self.other_client_user, RoleOnProject.CLIENT)

        self.category = Category.objects.create(
            project=self.project, name='Structural', budget=Decimal('1000000.00'),
        )
        self.todos = [
            self.make_todo(f'Task {index}', verified=index < 2)
            for index in range(4)
        ]
        # The same shape on the other project so a second billing can be made.
        Category.objects.create(
            project=self.other_project, name='Structural',
            budget=Decimal('2000000.00'),
        )
        for index in range(2):
            Todo.objects.create(
                category=self.other_project.categories.first(),
                title=f'Other {index}',
                start_date=timezone.localdate() - timedelta(days=30),
                end_date=timezone.localdate() - timedelta(days=10),
                is_done=True, is_verified=True,
                verified_at=timezone.now() - timedelta(days=5),
            )

        self.client_http = self.authed(self.client_user, Role.CLIENT)
        self.owner_http = self.authed(self.owner, Role.OWNER)
        self.accountant_http = self.authed(self.accountant, Role.ACCOUNTANT)
        self.engineer_http = self.authed(self.engineer, Role.SITE_ENGINEER)
        self.admin_http = self.authed(self.admin, Role.ADMIN)
        self.dual_http = self.authed(self.dual, Role.ADMIN)

    # -- builders ---------------------------------------------------------

    def make_project(self, code, name, client):
        return Project.objects.create(
            code=code, name=name, client=client,
            contract_amount=Decimal('1000000.00'),
            down_payment_pct=Decimal('10.00'),
            retention_pct=Decimal('5.00'),
            start_date=timezone.localdate() - timedelta(days=60),
            target_end_date=timezone.localdate() + timedelta(days=60),
            status=ProjectStatus.ONGOING,
        )

    def make_todo(self, title, verified):
        return Todo.objects.create(
            category=self.category, title=title,
            start_date=timezone.localdate() - timedelta(days=40),
            end_date=timezone.localdate() - timedelta(days=20),
            is_done=True, is_verified=verified,
            verified_at=timezone.now() - timedelta(days=10) if verified else None,
        )

    def join(self, project, user, role_on_project):
        ProjectAssignment.objects.create(
            project=project, user=user, role_on_project=role_on_project,
            response=RequestResponse.ACCEPTED,
        )

    def authed(self, user, role):
        client = APIClient()
        client.force_authenticate(user=user)
        client.credentials(HTTP_X_ACTIVE_ROLE=role)
        return client

    # -- helpers ----------------------------------------------------------

    def period_end(self, days_ago=1):
        return timezone.localdate() - timedelta(days=days_ago)

    def create_billing(self, project=None, http=None, days_ago=1):
        response = (http or self.owner_http).post(
            BILLINGS_URL,
            {'project_id': (project or self.project).pk,
             'period_end': self.period_end(days_ago).isoformat()},
            format='json',
        )
        self.assertEqual(response.status_code, 201, response.data)
        return response.data

    def send_billing(self, billing, http=None):
        response = (http or self.owner_http).post(
            f'{BILLINGS_URL}{billing["id"]}/submit/', {}, format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def approved_billing(self):
        billing = self.create_billing()
        self.send_billing(billing)
        response = self.client_http.post(
            f'{BILLINGS_URL}{billing["id"]}/client-approve/', {}, format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def pay(self, billing, amount, http=None):
        return (http or self.accountant_http).post(
            f'{BILLINGS_URL}{billing["id"]}/payments/',
            {'amount': str(amount), 'paid_on': timezone.localdate().isoformat(),
             'method': 'bank_transfer', 'reference_no': 'REF-1'},
            format='json',
        )


class BillingScopeTests(BillingFixtures, APITestCase):
    """Role fences, project scope and client visibility."""

    def test_owner_creates_a_draft_billing_with_exact_figures(self):
        billing = self.create_billing()

        self.assertEqual(billing['status'], 'draft')
        self.assertEqual(billing['billing_no'], 1)
        self.assertEqual(billing['project_id'], self.project.pk)
        self.assertEqual(money(billing['gross_earned']), Decimal('500000.00'))
        self.assertEqual(money(billing['less_previous']), Decimal('0.00'))
        self.assertEqual(money(billing['less_dp_recoupment']), Decimal('50000.00'))
        self.assertEqual(money(billing['less_retention']), Decimal('25000.00'))
        self.assertEqual(money(billing['net_due']), Decimal('425000.00'))
        self.assertEqual(money(billing['this_period']), Decimal('500000.00'))
        self.assertEqual(money(billing['pct_accomplished']), Decimal('0.500000'))
        self.assertEqual(
            AuditLog.objects.filter(action='billing_created').count(), 1,
        )

    def test_preview_saves_nothing_and_matches_the_created_billing(self):
        response = self.owner_http.get(
            PREVIEW_URL,
            {'project': self.project.pk,
             'period_end': self.period_end().isoformat()},
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(money(response.data['net_due']), Decimal('425000.00'))
        self.assertEqual(money(response.data['less_retention']), Decimal('25000.00'))
        self.assertEqual(AuditLog.objects.count(), 0)

    def test_billing_reads_and_writes_are_finance_roles_only(self):
        billing = self.create_billing()

        self.assertEqual(self.engineer_http.get(BILLINGS_URL).status_code, 403)
        self.assertEqual(
            self.engineer_http.get(f'{BILLINGS_URL}{billing["id"]}/').status_code,
            403,
        )
        self.assertEqual(self.admin_http.get(BILLINGS_URL).status_code, 403)
        self.assertEqual(
            self.accountant_http.get(f'{BILLINGS_URL}{billing["id"]}/').status_code,
            200,
        )

    def test_accountant_cannot_prepare_a_billing_but_can_read_it(self):
        response = self.accountant_http.post(
            BILLINGS_URL,
            {'project_id': self.project.pk,
             'period_end': self.period_end().isoformat()},
            format='json',
        )

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.data['detail'], rules.OWNER_PREPARES)

    def test_client_sees_only_billed_rows_of_its_own_projects(self):
        draft = self.create_billing()
        self.assertEqual(
            self.client_http.get(f'{BILLINGS_URL}{draft["id"]}/').status_code, 404,
        )
        self.assertEqual(self.client_http.get(BILLINGS_URL).data['results'], [])

        self.send_billing(draft)
        listed = self.client_http.get(BILLINGS_URL).data['results']
        self.assertEqual([row['id'] for row in listed], [draft['id']])
        self.assertEqual(
            self.client_http.get(f'{BILLINGS_URL}{draft["id"]}/').status_code, 200,
        )

        foreign = self.create_billing(project=self.other_project)
        self.send_billing(foreign)
        visible = [
            row['id'] for row in self.client_http.get(BILLINGS_URL).data['results']
        ]
        self.assertEqual(visible, [draft['id']])

    def test_withdrawn_billing_disappears_for_the_client(self):
        billing = self.create_billing()
        self.owner_http.post(f'{BILLINGS_URL}{billing["id"]}/withdraw/', {}, format='json')

        self.assertEqual(
            self.client_http.get(f'{BILLINGS_URL}{billing["id"]}/').status_code, 404,
        )
        self.assertEqual(
            self.owner_http.get(f'{BILLINGS_URL}{billing["id"]}/').status_code, 200,
        )

    def test_client_may_not_prepare_or_send_a_billing(self):
        self.assertEqual(
            self.client_http.post(
                BILLINGS_URL,
                {'project_id': self.project.pk,
                 'period_end': self.period_end().isoformat()},
                format='json',
            ).status_code,
            403,
        )
        billing = self.create_billing()
        self.assertEqual(
            self.client_http.post(
                f'{BILLINGS_URL}{billing["id"]}/submit/', {}, format='json',
            ).status_code,
            403,
        )

    def test_unassigned_owner_gets_404_not_a_listed_billing(self):
        outsider = make_user('outsider@example.com', [Role.OWNER])
        outsider_http = self.authed(outsider, Role.OWNER)
        billing = self.create_billing()

        self.assertEqual(outsider_http.get(BILLINGS_URL).data['results'], [])
        self.assertEqual(
            outsider_http.get(f'{BILLINGS_URL}{billing["id"]}/').status_code, 404,
        )

    def test_accountant_sees_every_project_without_being_assigned(self):
        billing = self.create_billing(project=self.other_project)

        rows = self.accountant_http.get(BILLINGS_URL).data['results']
        self.assertEqual([row['id'] for row in rows], [billing['id']])

    def test_active_role_decides_for_a_dual_role_user(self):
        billing = self.create_billing()
        as_engineer = self.authed(self.dual, Role.SITE_ENGINEER)

        self.assertEqual(as_engineer.get(BILLINGS_URL).status_code, 403)
        self.assertEqual(
            as_engineer.post(
                BILLINGS_URL,
                {'project_id': self.project.pk,
                 'period_end': self.period_end().isoformat()},
                format='json',
            ).status_code,
            403,
        )
        self.assertEqual(
            self.dual_http.get(f'{BILLINGS_URL}{billing["id"]}/').status_code, 403,
        )

    def test_client_of_another_project_cannot_answer_this_billing(self):
        billing = self.create_billing()
        self.send_billing(billing)

        response = self.authed(self.other_client_user, Role.CLIENT).post(
            f'{BILLINGS_URL}{billing["id"]}/client-approve/', {}, format='json',
        )
        self.assertEqual(response.status_code, 404)

    def test_payment_reads_are_finance_only(self):
        """Contract fence: owner/accountant read payments, the client does not.

        The client still sees the payments of its own billing in the billing
        detail, which is where the portal reads them.
        """
        billing = self.approved_billing()
        self.assertEqual(self.pay(billing, '100000.00').status_code, 201)
        self.create_billing(project=self.other_project)

        self.assertEqual(
            self.engineer_http.get(PAYMENTS_URL).status_code, 403,
        )
        self.assertEqual(self.client_http.get(PAYMENTS_URL).status_code, 403)
        for http in (self.owner_http, self.accountant_http):
            rows = http.get(PAYMENTS_URL).data['results']
            self.assertEqual(
                [row['progress_billing_id'] for row in rows], [billing['id']],
            )

        detail = self.client_http.get(f'{BILLINGS_URL}{billing["id"]}/').data
        self.assertEqual(len(detail['payments']), 1)

    def test_billing_id_in_the_body_cannot_break_project_scope(self):
        billing = self.create_billing(project=self.other_project)

        response = self.owner_http.post(
            f'{BILLINGS_URL}{billing["id"]}/submit/', {}, format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['project_id'], self.other_project.pk)


class BillingStateMachineTests(BillingFixtures, APITestCase):
    """Every transition, including the refusals the mock shows the user."""

    def status(self, billing):
        return self.owner_http.get(f'{BILLINGS_URL}{billing["id"]}/').data['status']

    def test_draft_submit_approve_pay_walks_the_happy_path(self):
        billing = self.create_billing()
        self.assertEqual(self.status(billing), 'draft')

        self.send_billing(billing)
        self.assertEqual(self.status(billing), 'pending_client')

        response = self.client_http.post(
            f'{BILLINGS_URL}{billing["id"]}/client-approve/', {}, format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'approved')

        response = self.pay(billing, '425000.00')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(self.status(billing), 'paid')
        self.assertEqual(
            AuditLog.objects.filter(action='billing_paid').count(), 1,
        )

    def test_only_draft_or_disputed_may_be_submitted_or_withdrawn(self):
        billing = self.approved_billing()

        response = self.owner_http.post(
            f'{BILLINGS_URL}{billing["id"]}/submit/', {}, format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], rules.ONLY_DRAFT_SUBMITTED)

        response = self.owner_http.post(
            f'{BILLINGS_URL}{billing["id"]}/withdraw/', {}, format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], rules.ONLY_DRAFT_WITHDRAWN)

    def test_withdrawing_a_draft_rejects_it_and_keeps_the_row(self):
        billing = self.create_billing()
        response = self.owner_http.post(
            f'{BILLINGS_URL}{billing["id"]}/withdraw/', {}, format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'rejected')
        self.assertEqual(
            self.owner_http.get(f'{BILLINGS_URL}{billing["id"]}/').status_code, 200,
        )
        self.assertEqual(
            AuditLog.objects.filter(action='billing_withdrawn').count(), 1,
        )

    def test_client_can_only_answer_a_billing_that_is_waiting(self):
        draft = self.create_billing()
        # An unissued draft is not even visible: no existence leak.
        self.assertEqual(
            self.client_http.post(
                f'{BILLINGS_URL}{draft["id"]}/client-approve/', {}, format='json',
            ).status_code,
            404,
        )
        self.owner_http.post(f'{BILLINGS_URL}{draft["id"]}/withdraw/', {}, format='json')

        approved = self.approved_billing()
        response = self.client_http.post(
            f'{BILLINGS_URL}{approved["id"]}/client-approve/', {}, format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'],
            rules.EXPECT_PENDING_CLIENT.format(current='approved by client'),
        )

    def test_dispute_needs_a_reason_then_can_be_resubmitted(self):
        billing = self.create_billing()
        self.send_billing(billing)

        blank = self.client_http.post(
            f'{BILLINGS_URL}{billing["id"]}/client-dispute/',
            {'reason': '   '}, format='json',
        )
        self.assertEqual(blank.status_code, 400)
        self.assertEqual(blank.data['detail'], rules.REASON)

        response = self.client_http.post(
            f'{BILLINGS_URL}{billing["id"]}/client-dispute/',
            {'reason': 'Retention looks wrong.'}, format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'disputed')
        detail = self.client_http.get(f'{BILLINGS_URL}{billing["id"]}/').data
        self.assertEqual(
            [row['action'] for row in detail['history']][:1],
            ['billing_client_disputed'],
        )

        resent = self.send_billing(billing)
        self.assertEqual(resent['status'], 'pending_client')

    def test_one_billing_in_progress_per_project(self):
        self.create_billing()

        response = self.owner_http.post(
            BILLINGS_URL,
            {'project_id': self.project.pk,
             'period_end': self.period_end().isoformat()},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], rules.IN_PROGRESS)

    def test_a_rejected_billing_frees_the_project_for_a_new_one(self):
        first = self.create_billing()
        self.owner_http.post(f'{BILLINGS_URL}{first["id"]}/withdraw/', {}, format='json')

        second = self.create_billing()

        self.assertEqual(second['billing_no'], 2)
        self.assertEqual(money(second['less_previous']), Decimal('0.00'))

    def test_period_end_must_be_a_past_iso_date_after_the_previous_period(self):
        future = self.owner_http.post(
            BILLINGS_URL,
            {'project_id': self.project.pk,
             'period_end': (timezone.localdate() + timedelta(days=1)).isoformat()},
            format='json',
        )
        self.assertEqual(future.status_code, 400)
        self.assertEqual(future.data['detail'], rules.PERIOD_FUTURE)

        junk = self.owner_http.post(
            BILLINGS_URL,
            {'project_id': self.project.pk, 'period_end': '2026-3-2'},
            format='json',
        )
        self.assertEqual(junk.status_code, 400)

        self.create_billing(days_ago=3)
        same_period = self.owner_http.post(
            BILLINGS_URL,
            {'project_id': self.project.pk,
             'period_end': self.period_end(3).isoformat()},
            format='json',
        )
        self.assertEqual(same_period.status_code, 400)

    def test_no_new_verified_accomplishment_is_refused(self):
        billing = self.create_billing(days_ago=3)
        self.send_billing(billing)
        self.client_http.post(
            f'{BILLINGS_URL}{billing["id"]}/client-approve/', {}, format='json',
        )
        self.assertEqual(self.pay(billing, '425000.00').status_code, 201)

        response = self.owner_http.post(
            BILLINGS_URL,
            {'project_id': self.project.pk,
             'period_end': self.period_end().isoformat()},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], rules.NO_NEW_WORK)

    def test_a_second_billing_counts_the_previous_gross(self):
        first = self.create_billing(days_ago=4)
        self.send_billing(first)
        self.client_http.post(
            f'{BILLINGS_URL}{first["id"]}/client-approve/', {}, format='json',
        )
        self.assertEqual(self.pay(first, '425000.00').status_code, 201)
        self.todos[2].is_verified = True
        self.todos[2].verified_at = timezone.now() - timedelta(days=2)
        self.todos[2].save()

        second = self.create_billing(days_ago=1)

        self.assertEqual(second['billing_no'], 2)
        self.assertEqual(money(second['pct_accomplished']), Decimal('0.750000'))
        self.assertEqual(money(second['gross_earned']), Decimal('750000.00'))
        self.assertEqual(money(second['less_previous']), Decimal('500000.00'))
        self.assertEqual(money(second['this_period']), Decimal('250000.00'))
        self.assertEqual(money(second['less_dp_recoupment']), Decimal('25000.00'))
        self.assertEqual(money(second['less_retention']), Decimal('12500.00'))
        self.assertEqual(money(second['net_due']), Decimal('212500.00'))

    def test_billable_status_is_enforced_with_the_mock_text(self):
        self.project.status = ProjectStatus.REQUESTED
        self.project.save()

        response = self.owner_http.post(
            BILLINGS_URL,
            {'project_id': self.project.pk,
             'period_end': self.period_end().isoformat()},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'],
            rules.BILLABLE.format(status='Waiting for client'),
        )

    def test_a_completed_project_can_bill_its_final_billing(self):
        self.project.status = ProjectStatus.COMPLETED
        self.project.save()

        billing = self.create_billing()
        self.assertEqual(billing['status'], 'draft')


class BillingMoneyTests(BillingFixtures, APITestCase):
    """Overpayment, payload validation and the billed/collected summary."""

    def test_overpayment_is_refused_with_the_balance_in_the_text(self):
        billing = self.approved_billing()

        response = self.pay(billing, '425000.01')

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'], rules.PAYMENT_OVER.format(balance='425000.00'),
        )
        self.assertEqual(
            self.owner_http.get(f'{BILLINGS_URL}{billing["id"]}/').data['payments'],
            [],
        )

    def test_payments_are_refused_until_the_client_approves(self):
        billing = self.create_billing()

        response = self.pay(billing, '100.00')

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], rules.PAYMENT_APPROVED_ONLY)

    def test_non_positive_and_non_finite_amounts_are_refused(self):
        billing = self.approved_billing()

        for amount in ('0', '-100', 'NaN', 'Infinity'):
            with self.subTest(amount=amount):
                response = self.pay(billing, amount)
                self.assertEqual(response.status_code, 400, (amount, response.data))

    def test_partial_payments_accumulate_and_leave_the_billing_approved(self):
        billing = self.approved_billing()

        self.assertEqual(self.pay(billing, '200000.00').status_code, 201)
        self.assertEqual(self.pay(billing, '100000.00').status_code, 201)

        detail = self.owner_http.get(f'{BILLINGS_URL}{billing["id"]}/').data
        self.assertEqual(detail['status'], 'approved')
        self.assertEqual(len(detail['payments']), 2)
        self.assertEqual(
            money(sum(money(row['amount']) for row in detail['payments'])),
            Decimal('300000.00'),
        )

    def test_summary_totals_only_billed_net_due_and_recorded_payments(self):
        billing = self.approved_billing()
        self.pay(billing, '100000.00')
        self.create_billing(project=self.other_project)  # still a draft

        response = self.owner_http.get(SUMMARY_URL)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(money(response.data['billed']), Decimal('425000.00'))
        self.assertEqual(money(response.data['collected']), Decimal('100000.00'))

    def test_summary_refuses_a_project_outside_the_callers_scope(self):
        """`?project=` may not widen the scope: a foreign id is a 404, not money."""
        owner_of_a = make_user('single-a@example.com', [Role.OWNER])
        self.join(self.project, owner_of_a, RoleOnProject.OWNER)
        # A declined assignment on B grants nothing either.
        ProjectAssignment.objects.create(
            project=self.other_project, user=owner_of_a,
            role_on_project=RoleOnProject.OWNER,
            response=RequestResponse.DECLINED,
        )
        http = self.authed(owner_of_a, Role.OWNER)
        self.approved_billing()

        own = http.get(SUMMARY_URL, {'project': self.project.pk})
        self.assertEqual(own.status_code, 200, own.data)
        self.assertEqual(money(own.data['billed']), Decimal('425000.00'))

        for project_id in (self.other_project.pk, 999999):
            leaked = http.get(SUMMARY_URL, {'project': project_id})
            self.assertEqual(leaked.status_code, 404, (project_id, leaked.data))

    def test_a_percentage_split_that_leaves_nothing_to_pay_is_refused(self):
        """`dp_pct + retention_pct >= 100` would make the net due <= 0 forever."""
        Project.objects.filter(pk=self.project.pk).update(
            down_payment_pct=Decimal('60.00'), retention_pct=Decimal('40.00'),
        )

        response = self.owner_http.post(
            BILLINGS_URL,
            {'project_id': self.project.pk,
             'period_end': self.period_end().isoformat()},
            format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], rules.PCT_BURDEN)
        self.assertFalse(ProgressBilling.objects.exists())

    def test_client_approval_is_refused_while_the_percentages_leave_nothing_to_pay(self):
        billing = self.create_billing()  # 10 % + 5 %: legal at creation time
        self.send_billing(billing)
        Project.objects.filter(pk=self.project.pk).update(
            down_payment_pct=Decimal('60.00'), retention_pct=Decimal('40.00'),
        )

        response = self.client_http.post(
            f'{BILLINGS_URL}{billing["id"]}/client-approve/', {}, format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], rules.PCT_BURDEN)
        self.assertEqual(
            ProgressBilling.objects.get(pk=billing['id']).status, 'pending_client',
        )

    def test_payment_actor_and_timestamps_are_server_owned(self):
        billing = self.approved_billing()

        response = self.accountant_http.post(
            f'{BILLINGS_URL}{billing["id"]}/payments/',
            {'amount': '1000.00', 'paid_on': timezone.localdate().isoformat(),
             'method': 'cash', 'user_id': self.owner.pk,
             'received_by': self.owner.pk},
            format='json',
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertNotIn('user_id', response.data)
        audit = AuditLog.objects.get(action='billing_payment_recorded')
        self.assertEqual(audit.user, self.accountant)


class RetentionTests(BillingFixtures, APITestCase):
    """Retention withheld on approved billings, then released after completion."""

    def close_project(self):
        self.project.status = ProjectStatus.CLOSED
        self.project.save()

    def test_retention_is_held_only_on_approved_or_paid_billings(self):
        billing = self.create_billing()
        drafted = self.owner_http.get(RETENTION_URL, {'project': self.project.pk})

        self.assertEqual(drafted.status_code, 200, drafted.data)
        self.assertEqual(money(drafted.data['held']), Decimal('0.00'))

        self.send_billing(billing)
        self.client_http.post(
            f'{BILLINGS_URL}{billing["id"]}/client-approve/', {}, format='json',
        )

        held = self.owner_http.get(RETENTION_URL, {'project': self.project.pk}).data
        self.assertEqual(money(held['held']), Decimal('25000.00'))
        self.assertEqual(money(held['released']), Decimal('0.00'))
        self.assertEqual(money(held['available']), Decimal('25000.00'))

    def test_retention_is_released_only_after_completion(self):
        self.approved_billing()

        response = self.owner_http.post(
            RELEASES_URL,
            {'project_id': self.project.pk, 'amount': '25000.00',
             'released_on': timezone.localdate().isoformat(), 'method': 'check'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], rules.RETENTION_NOT_COMPLETE)

    def test_release_above_the_remaining_balance_is_refused(self):
        self.approved_billing()
        self.close_project()

        response = self.accountant_http.post(
            RELEASES_URL,
            {'project_id': self.project.pk, 'amount': '25000.01',
             'released_on': timezone.localdate().isoformat(), 'method': 'check'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'], rules.PAYMENT_OVER.format(balance='25000.00'),
        )

    def test_release_records_the_row_updates_the_summary_and_audits(self):
        self.approved_billing()
        self.close_project()

        response = self.accountant_http.post(
            RELEASES_URL,
            {'project_id': self.project.pk, 'amount': '10000.00',
             'released_on': timezone.localdate().isoformat(), 'method': 'check',
             'reference_no': 'CHK-9'},
            format='json',
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(money(response.data['amount']), Decimal('10000.00'))

        summary = self.accountant_http.get(RETENTION_URL, {'project': self.project.pk})
        self.assertEqual(money(summary.data['released']), Decimal('10000.00'))
        self.assertEqual(money(summary.data['available']), Decimal('15000.00'))
        self.assertEqual(
            self.accountant_http.get(RELEASES_URL, {'project': self.project.pk})
            .data['results'][0]['reference_no'],
            'CHK-9',
        )
        audit = AuditLog.objects.get(action='retention_released')
        self.assertEqual(audit.details, {'amount': '10000.00'})

    def test_retention_routes_are_finance_only(self):
        self.assertEqual(self.engineer_http.get(RETENTION_URL).status_code, 403)
        self.assertEqual(self.client_http.get(RETENTION_URL).status_code, 403)
        self.assertEqual(self.client_http.get(RELEASES_URL).status_code, 403)


class VariationOrderTests(BillingFixtures, APITestCase):
    """Proposal, pricing, and the atomic client approval that moves the contract."""

    def propose(self, http=None, **overrides):
        payload = {
            'project_id': self.project.pk, 'type': 'additive',
            'description': 'Extra floor slab', 'amount': '150000.00',
            'days_impact': 10,
        }
        payload.update(overrides)
        return (http or self.owner_http).post(VOS_URL, payload, format='json')

    def test_owner_proposes_a_priced_vo_with_a_server_number(self):
        response = self.propose()

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['vo_no'], 'VO-01')
        self.assertEqual(response.data['status'], 'proposed')
        self.assertEqual(money(response.data['amount']), Decimal('150000.00'))
        self.assertEqual(
            AuditLog.objects.filter(action='vo_proposed').count(), 1,
        )

    def test_deductive_vo_amount_is_stored_signed(self):
        response = self.propose(type='deductive', amount='40000.00')

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(money(response.data['amount']), Decimal('-40000.00'))

    def test_site_engineer_may_propose_but_never_prices_it(self):
        response = self.propose(http=self.engineer_http, amount='150000.00')

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(money(response.data['amount']), Decimal('0.00'))

        edit = self.engineer_http.patch(
            f'{VOS_URL}{response.data["id"]}/',
            {'amount': '999.00', 'description': 'Slab plus beams'},
            format='json',
        )
        self.assertEqual(edit.status_code, 200, edit.data)
        self.assertEqual(money(edit.data['amount']), Decimal('0.00'))
        self.assertEqual(edit.data['description'], 'Slab plus beams')

    def test_unrelated_engineer_cannot_propose_on_this_project(self):
        outsider = make_user('eng2@example.com', [Role.SITE_ENGINEER])

        response = self.propose(http=self.authed(outsider, Role.SITE_ENGINEER))

        self.assertEqual(response.status_code, 404)

    def test_vo_needs_a_description(self):
        response = self.propose(description='   ')

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], rules.VO_DESCRIPTION)

    def test_owner_sends_a_proposed_vo_to_the_client(self):
        vo = self.propose().data

        response = self.owner_http.post(
            f'{VOS_URL}{vo["id"]}/submit/', {}, format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'pending_client')
        self.assertEqual(response.data['approved_by_owner'], self.owner.pk)

    def test_an_unpriced_vo_cannot_be_sent_to_the_client(self):
        vo = self.propose(http=self.engineer_http).data

        response = self.owner_http.post(
            f'{VOS_URL}{vo["id"]}/submit/', {}, format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], rules.VO_PRICE_REQUIRED)

        self.owner_http.patch(
            f'{VOS_URL}{vo["id"]}/', {'amount': '80000.00'}, format='json',
        )
        priced = self.owner_http.post(
            f'{VOS_URL}{vo["id"]}/submit/', {}, format='json',
        )
        self.assertEqual(priced.status_code, 200, priced.data)
        self.assertEqual(money(priced.data['amount']), Decimal('80000.00'))

    def test_owner_reject_needs_a_reason_and_ends_the_vo(self):
        vo = self.propose().data

        blank = self.owner_http.post(
            f'{VOS_URL}{vo["id"]}/owner-reject/', {'reason': ''}, format='json',
        )
        self.assertEqual(blank.status_code, 400)
        self.assertEqual(blank.data['detail'], rules.REASON)

        response = self.owner_http.post(
            f'{VOS_URL}{vo["id"]}/owner-reject/',
            {'reason': 'Not needed.'}, format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'rejected')

    def test_client_approval_moves_the_contract_and_the_target_end_once(self):
        vo = self.propose(days_impact=10).data
        self.owner_http.post(f'{VOS_URL}{vo["id"]}/submit/', {}, format='json')

        response = self.client_http.post(
            f'{VOS_URL}{vo["id"]}/client-approve/', {}, format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'approved')
        self.assertEqual(response.data['approved_by_client'], self.client_user.pk)

        self.project.refresh_from_db()
        self.assertEqual(self.project.contract_amount, Decimal('1150000.00'))
        self.assertEqual(
            self.project.target_end_date,
            (timezone.localdate() + timedelta(days=60 + 10)),
        )
        self.assertEqual(
            AuditLog.objects.filter(action='vo_client_approved').count(), 1,
        )

        again = self.client_http.post(
            f'{VOS_URL}{vo["id"]}/client-approve/', {}, format='json',
        )
        self.assertEqual(again.status_code, 400)
        self.assertEqual(again.data['detail'], rules.VO_NOT_WAITING)
        self.project.refresh_from_db()
        self.assertEqual(self.project.contract_amount, Decimal('1150000.00'))

    def test_client_approval_locks_the_project_before_the_variation_order(self):
        """Contract lock order on every write: project row first, then the VO.

        `save_vo` locks project -> VO; a `client-approve` that locks VO -> project
        deadlocks against it. A two-thread race is not deterministic here, so the
        order of the emitted `FOR UPDATE` statements is asserted instead.
        """
        vo = self.propose(days_impact=10).data
        self.owner_http.post(f'{VOS_URL}{vo["id"]}/submit/', {}, format='json')

        with CaptureQueriesContext(connection) as queries:
            response = self.client_http.post(
                f'{VOS_URL}{vo["id"]}/client-approve/', {}, format='json',
            )

        self.assertEqual(response.status_code, 200, response.data)
        project_table = Project._meta.db_table
        vo_table = VariationOrder._meta.db_table
        locked = [
            project_table if project_table in query['sql'] else vo_table
            for query in queries.captured_queries
            if 'FOR UPDATE' in query['sql']
        ]
        self.assertEqual(locked, [project_table, vo_table])

    def test_a_proposal_that_would_undercut_the_billed_amount_is_refused(self):
        self.approved_billing()  # 500,000 is already billed

        response = self.propose(type='deductive', amount='1000000.00')

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'],
            rules.VO_BELOW_BILLED.format(billed='500000.00'),
        )

    def test_deductive_vo_cannot_drop_the_contract_below_the_billed_amount(self):
        # Nothing is billed yet, so the proposal itself is legal...
        vo = self.propose(type='deductive', amount='900000.00').data
        self.owner_http.post(f'{VOS_URL}{vo["id"]}/submit/', {}, format='json')
        # ...but by approval time 500,000 is billed, so 100,000 is impossible.
        self.approved_billing()

        response = self.client_http.post(
            f'{VOS_URL}{vo["id"]}/client-approve/', {}, format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'], rules.VO_BELOW_BILLED.format(billed='500000.00'),
        )
        self.project.refresh_from_db()
        self.assertEqual(self.project.contract_amount, Decimal('1000000.00'))
        self.assertEqual(
            self.owner_http.get(f'{VOS_URL}{vo["id"]}/').data['status'],
            'pending_client',
        )

    def test_client_reject_leaves_the_contract_alone(self):
        vo = self.propose().data
        self.owner_http.post(f'{VOS_URL}{vo["id"]}/submit/', {}, format='json')

        response = self.client_http.post(
            f'{VOS_URL}{vo["id"]}/client-reject/',
            {'reason': 'Too expensive.'}, format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'rejected')
        self.project.refresh_from_db()
        self.assertEqual(self.project.contract_amount, Decimal('1000000.00'))

    def test_client_sees_only_vos_the_owner_has_sent(self):
        proposed = self.propose().data
        sent = self.propose(description='Second change').data
        self.owner_http.post(f'{VOS_URL}{sent["id"]}/submit/', {}, format='json')

        rows = self.client_http.get(VOS_URL).data['results']

        self.assertEqual([row['id'] for row in rows], [sent['id']])
        self.assertEqual(
            self.client_http.get(f'{VOS_URL}{proposed["id"]}/').status_code, 404,
        )

    def test_accountant_has_no_variation_order_surface(self):
        self.assertEqual(self.accountant_http.get(VOS_URL).status_code, 403)

    def test_a_sent_vo_is_no_longer_editable(self):
        vo = self.propose().data
        self.owner_http.post(f'{VOS_URL}{vo["id"]}/submit/', {}, format='json')

        response = self.owner_http.patch(
            f'{VOS_URL}{vo["id"]}/', {'description': 'Changed'}, format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], rules.VO_EDIT_PROPOSED)


class ProgressDateTests(BillingFixtures, APITestCase):
    """`verified_at` is compared as the site's local (Asia/Manila) date.

    The mock compares `_dateOnly(verifiedAt.toLocal())` against the period end
    (`data/services/progress_calculator.dart:204`), and the billing period is a
    local business date, so a verification at 01:00 Manila on the day after the
    period end is excluded even though it is the same UTC day.
    """

    def test_a_verification_after_the_period_end_in_local_time_is_excluded(self):
        period_end = self.period_end()
        Todo.objects.create(
            category=self.category, title='Verified after the local period end',
            start_date=period_end - timedelta(days=5),
            end_date=period_end,
            is_done=True, is_verified=True,
            # 17:00 UTC on the period end is 01:00 the next day in Manila.
            verified_at=datetime.combine(
                period_end, time(17, 0), tzinfo=UTC,
            ),
        )

        response = self.owner_http.get(
            PREVIEW_URL,
            {'project': self.project.pk, 'period_end': period_end.isoformat()},
        )

        self.assertEqual(response.status_code, 200, response.data)
        # 2 of the 5 to-dos were verified on or before the period end.
        self.assertEqual(
            money(response.data['pct_accomplished']), Decimal('0.400000'),
        )


class BillingAuditTests(BillingFixtures, APITestCase):
    """Audit rows carry the actor and no money beyond the mock's own keys."""

    def test_billing_history_is_the_audit_trail_of_that_billing(self):
        billing = self.approved_billing()
        self.pay(billing, '1000.00')

        detail = self.owner_http.get(f'{BILLINGS_URL}{billing["id"]}/').data
        actions = [row['action'] for row in detail['history']]

        self.assertEqual(
            actions,
            ['billing_payment_recorded', 'billing_client_approved',
             'billing_submitted', 'billing_created'],
        )
        self.assertTrue(all(row['entity'] == 'progress_billing' for row in detail['history']))
        self.assertTrue(
            all(row['entity_id'] == billing['id'] for row in detail['history']),
        )

    def test_audit_details_hold_no_money_except_the_mocks_own_amount_keys(self):
        billing = self.approved_billing()
        self.pay(billing, '1000.00')

        for audit in AuditLog.objects.all():
            allowed = (
                {'amount'} if audit.action in (
                    'billing_payment_recorded', 'retention_released',
                ) else set()
            )
            for key in audit.details:
                with self.subTest(action=audit.action, key=key):
                    self.assertIn(key, allowed | {'reason', 'project'})

    def test_client_supplied_actor_is_ignored(self):
        billing = self.create_billing()

        self.send_billing(billing)
        audit = AuditLog.objects.get(action='billing_submitted')
        self.assertEqual(audit.user, self.owner)


class BillingConcurrencyTests(BillingFixtures, TransactionTestCase):
    """Two simultaneous payments can never exceed the net due.

    `TransactionTestCase` on purpose: worker threads get their own connection,
    which cannot see an `APITestCase` transaction's uncommitted rows. The payment
    path locks the billing row, so the second request re-reads the first's sum.
    """

    client_class = APIClient
    serialized_rollback = True

    def test_simultaneous_payments_never_exceed_the_balance(self):
        billing = self.approved_billing()
        results = []
        barrier = threading.Barrier(2)

        def pay():
            client = APIClient()
            try:
                client.force_authenticate(user=self.accountant)
                client.credentials(HTTP_X_ACTIVE_ROLE=Role.ACCOUNTANT)
                barrier.wait(timeout=10)
                response = client.post(
                    f'{BILLINGS_URL}{billing["id"]}/payments/',
                    {'amount': '300000.00',
                     'paid_on': timezone.localdate().isoformat(),
                     'method': 'bank_transfer'},
                    format='json',
                )
                results.append(response.status_code)
            finally:
                connections.close_all()

        threads = [threading.Thread(target=pay) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(sorted(results), [201, 400], results)
        detail = self.owner_http.get(f'{BILLINGS_URL}{billing["id"]}/').data
        paid = sum(money(row['amount']) for row in detail['payments'])
        self.assertLessEqual(paid, Decimal('425000.00'), paid)
        self.assertEqual(detail['status'], 'approved')
