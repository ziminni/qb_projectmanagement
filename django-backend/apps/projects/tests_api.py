"""Phase 2.1 wire-contract tests: projects, assignments, categories and to-dos.

Every check in `planning/backend-integration/contracts/phase-2-projects-and-site.md`
under "Security checks this phase must prove with tests" that belongs to 2.1 has
a test here. Daily reports and documents are 2.2.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

from datetime import date
from decimal import Decimal
from unittest import mock

from django.db import IntegrityError
from rest_framework.test import APITestCase

from ..users.models import AuditLog, Notification, Role
from ..users.tests import make_user
from .models import (
    Category,
    Client,
    Project,
    ProjectAssignment,
    ProjectStatus,
    RequestResponse,
    RoleOnProject,
    Todo,
)

PROJECT_KEYS = {
    'id', 'code', 'name', 'location', 'latitude', 'longitude', 'client_id',
    'contract_amount', 'down_payment_pct', 'retention_pct', 'start_date',
    'target_end_date', 'actual_end_date', 'status', 'created_at', 'updated_at',
}
FINANCE_KEYS = {'contract_amount', 'down_payment_pct', 'retention_pct'}


class ProjectApiCase(APITestCase):
    """Five roles, clients, and two projects (A assigned, B not)."""

    def setUp(self):
        self.admin = make_user('admin@example.com', [Role.ADMIN])
        self.owner = make_user('maria@example.com', [Role.OWNER])
        self.other_owner = make_user('owner2@example.com', [Role.OWNER])
        self.engineer = make_user('ramon@example.com', [Role.SITE_ENGINEER])
        self.other_engineer = make_user('eng2@example.com', [Role.SITE_ENGINEER])
        self.accountant = make_user('liza@example.com', [Role.ACCOUNTANT])
        self.client_user = make_user('elena@example.com', [Role.CLIENT])
        self.client_record = Client.objects.create(
            name='Acme Holdings', user=self.client_user,
        )

        self.project = self.make_project('PRJ-A', 'Tower A')
        self.other_project = self.make_project('PRJ-B', 'Tower B')
        self.join(self.project, self.owner, RoleOnProject.OWNER)
        self.join(self.project, self.engineer, RoleOnProject.SITE_ENGINEER)
        self.join(self.project, self.client_user, RoleOnProject.CLIENT)
        self.category = Category.objects.create(
            project=self.project, name='Siteworks', sort_order=1,
            budget=Decimal('400000.00'),
        )
        self.todo = Todo.objects.create(
            category=self.category, title='Excavate',
            start_date=date(2026, 1, 5), end_date=date(2026, 1, 10),
        )

    # --- fixtures ---
    def make_project(self, code, name, **extra):
        defaults = {
            'location': 'Cebu City',
            'client': self.client_record,
            'contract_amount': Decimal('1000000.00'),
            'down_payment_pct': Decimal('15.00'),
            'retention_pct': Decimal('5.00'),
            'start_date': date(2026, 1, 1),
            'target_end_date': date(2026, 6, 30),
            'status': ProjectStatus.ACCEPTED,
        }
        defaults.update(extra)
        return Project.objects.create(code=code, name=name, **defaults)

    def join(self, project, user, role_on_project, response=RequestResponse.ACCEPTED):
        return ProjectAssignment.objects.create(
            project=project, user=user, role_on_project=role_on_project,
            response=response,
        )

    def act_as(self, user, role):
        """Send requests as `user` in `role` (the `X-Active-Role` header)."""
        self.client.force_authenticate(user=user)
        self.client.credentials(HTTP_X_ACTIVE_ROLE=role)

    def project_payload(self, **overrides):
        payload = {
            'code': 'prj-c1',
            'name': 'Warehouse C',
            'location': 'Davao',
            'latitude': '7.190700',
            'longitude': '125.455300',
            'client_id': self.client_record.pk,
            'contract_amount': '2000000.00',
            'down_payment_pct': '10.00',
            'retention_pct': '5.00',
            'start_date': '2026-02-01',
            'target_end_date': '2026-08-31',
        }
        payload.update(overrides)
        return payload


class ProjectReadScopeTests(ProjectApiCase):
    def test_admin_and_accountant_see_every_project(self):
        for user, role in ((self.admin, Role.ADMIN), (self.accountant, Role.ACCOUNTANT)):
            self.act_as(user, role)
            response = self.client.get('/api/v1/projects/')

            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual(
                {row['code'] for row in response.data}, {'PRJ-A', 'PRJ-B'},
            )

    def test_assigned_roles_see_only_their_own_projects(self):
        for user, role in (
            (self.owner, Role.OWNER),
            (self.engineer, Role.SITE_ENGINEER),
            (self.client_user, Role.CLIENT),
        ):
            self.act_as(user, role)
            response = self.client.get('/api/v1/projects/')

            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual([row['code'] for row in response.data], ['PRJ-A'])

    def test_pending_declined_and_not_sent_assignments_grant_no_scope(self):
        for response_value in (
            RequestResponse.PENDING,
            RequestResponse.DECLINED,
            RequestResponse.NOT_SENT,
            RequestResponse.CHANGES_REQUESTED,
        ):
            ProjectAssignment.objects.filter(user=self.other_engineer).delete()
            self.join(
                self.project, self.other_engineer,
                RoleOnProject.SITE_ENGINEER, response_value,
            )

            self.act_as(self.other_engineer, Role.SITE_ENGINEER)

            self.assertEqual(self.client.get('/api/v1/projects/').data, [])
            self.assertEqual(
                self.client.get(f'/api/v1/projects/{self.project.pk}/').status_code,
                404,
            )

    def test_client_sees_their_own_contract_terms(self):
        self.act_as(self.client_user, Role.CLIENT)

        response = self.client.get(f'/api/v1/projects/{self.project.pk}/')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(set(response.data), PROJECT_KEYS)
        self.assertEqual(Decimal(response.data['contract_amount']), Decimal('1000000.00'))

    def test_finance_keys_are_omitted_for_admin_and_site_engineer(self):
        for user, role in (
            (self.admin, Role.ADMIN),
            (self.engineer, Role.SITE_ENGINEER),
        ):
            self.act_as(user, role)
            detail = self.client.get(f'/api/v1/projects/{self.project.pk}/')
            listing = self.client.get('/api/v1/projects/')

            self.assertEqual(detail.status_code, 200, detail.data)
            self.assertFalse(FINANCE_KEYS & set(detail.data), detail.data)
            self.assertFalse(FINANCE_KEYS & set(listing.data[0]), listing.data[0])

    def test_declined_projects_are_hidden_from_every_read(self):
        self.project.status = ProjectStatus.DECLINED
        self.project.save(update_fields=['status'])

        self.act_as(self.owner, Role.OWNER)

        self.assertEqual(self.client.get('/api/v1/projects/').data, [])
        self.assertEqual(
            self.client.get(f'/api/v1/projects/{self.project.pk}/').status_code, 404,
        )


class ProjectIdorTests(ProjectApiCase):
    """Another project's objects are 404 for every non-company-wide role."""

    def setUp(self):
        super().setUp()
        self.other_category = Category.objects.create(
            project=self.other_project, name='Finishes',
        )
        self.other_todo = Todo.objects.create(
            category=self.other_category, title='Paint',
            start_date=date(2026, 2, 1), end_date=date(2026, 2, 5),
        )
        self.other_assignment = self.join(
            self.other_project, self.other_owner, RoleOnProject.OWNER,
        )

    def routes_for_other_project(self):
        other_category = self.other_category
        other_todo = self.other_todo
        other_assignment = self.other_assignment
        b = self.other_project.pk
        return [
            ('get', f'/api/v1/projects/{b}/', None),
            ('patch', f'/api/v1/projects/{b}/', {'name': 'Hijacked'}),
            ('post', f'/api/v1/projects/{b}/status/', {'status': 'ongoing'}),
            ('post', f'/api/v1/projects/{b}/resend/', None),
            ('get', f'/api/v1/projects/{b}/assignments/', None),
            ('post', f'/api/v1/projects/{b}/assignments/',
             {'user_id': self.engineer.pk, 'role_on_project': 'owner'}),
            ('get', f'/api/v1/projects/{b}/categories/', None),
            ('post', f'/api/v1/projects/{b}/categories/', {'name': 'Hack'}),
            ('get', f'/api/v1/projects/{b}/todos/', None),
            ('patch', f'/api/v1/categories/{other_category.pk}/', {'name': 'Hack'}),
            ('delete', f'/api/v1/categories/{other_category.pk}/', None),
            ('patch', f'/api/v1/todos/{other_todo.pk}/', {'title': 'Hack'}),
            ('delete', f'/api/v1/todos/{other_todo.pk}/', None),
            ('post', f'/api/v1/todos/{other_todo.pk}/done/', {'done': True}),
            ('post', f'/api/v1/todos/{other_todo.pk}/verify/', None),
            ('post', f'/api/v1/todos/{other_todo.pk}/unverify/', {'reason': 'x'}),
            ('delete', f'/api/v1/project-assignments/{other_assignment.pk}/', None),
        ]

    def test_owner_site_engineer_and_client_get_404_across_projects(self):
        for user, role in (
            (self.owner, Role.OWNER),
            (self.engineer, Role.SITE_ENGINEER),
            (self.client_user, Role.CLIENT),
        ):
            self.act_as(user, role)
            for method, url, payload in self.routes_for_other_project():
                call = getattr(self.client, method)
                response = (
                    call(url, payload, format='json') if payload is not None
                    else call(url)
                )
                self.assertEqual(
                    response.status_code, 404,
                    f'{role} {method.upper()} {url} -> {response.status_code}'
                    f' {getattr(response, "data", "")}',
                )


class ProjectCreateTests(ProjectApiCase):
    def test_owner_create_returns_the_flutter_shape_and_assigns_themselves(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            '/api/v1/projects/', self.project_payload(), format='json',
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(set(response.data), PROJECT_KEYS)
        self.assertEqual(response.data['code'], 'PRJ-C1')
        self.assertEqual(response.data['status'], 'requested')
        project = Project.objects.get(pk=response.data['id'])
        assignment = project.assignments.get(user=self.owner)
        self.assertEqual(assignment.role_on_project, RoleOnProject.OWNER)
        self.assertEqual(assignment.response, RequestResponse.ACCEPTED)
        self.assertTrue(
            AuditLog.objects.filter(action='project_created', entity_id=project.pk).exists()
        )
        # The new project is in scope for the caller straight away.
        self.assertIn(
            project.pk,
            [row['id'] for row in self.client.get('/api/v1/projects/').data],
        )

    def test_only_an_owner_can_create_a_project(self):
        for user, role in (
            (self.admin, Role.ADMIN),
            (self.accountant, Role.ACCOUNTANT),
            (self.engineer, Role.SITE_ENGINEER),
            (self.client_user, Role.CLIENT),
        ):
            self.act_as(user, role)
            response = self.client.post(
                '/api/v1/projects/', self.project_payload(), format='json',
            )

            self.assertEqual(response.status_code, 403, response.data)
            self.assertEqual(
                response.data['detail'],
                'Only a project manager can create a project.',
            )

    def test_project_refusals_use_the_mock_texts(self):
        self.act_as(self.owner, Role.OWNER)
        cases = [
            ({'code': '   '}, 'Enter the project code.'),
            ({'name': ''}, 'Enter the project name.'),
            ({'contract_amount': '0'}, 'Contract amount must be greater than 0.'),
            ({'start_date': None, 'target_end_date': None},
             'Choose the start and target end dates.'),
            ({'target_end_date': '2026-02-01'},
             'Target end date must be after the start date.'),
            ({'down_payment_pct': '101'}, 'The down payment must be 0–100%.'),
            ({'retention_pct': '-1'}, 'The retention must be 0–100%.'),
            ({'client_id': None}, 'Choose the client.'),
        ]
        for override, message in cases:
            response = self.client.post(
                '/api/v1/projects/', self.project_payload(**override), format='json',
            )

            self.assertEqual(response.status_code, 400, (override, response.data))
            self.assertEqual(response.data['detail'], message)

    def test_a_client_without_a_login_cannot_be_chosen(self):
        self.act_as(self.owner, Role.OWNER)
        no_login = Client.objects.create(name='No Login Yet')

        response = self.client.post(
            '/api/v1/projects/',
            self.project_payload(client_id=no_login.pk), format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'],
            'This client has no app login yet. Ask the admin to create one.',
        )

    def test_project_code_is_case_insensitively_unique(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            '/api/v1/projects/', self.project_payload(code=' prj-a '), format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'], 'Another project already uses this code.',
        )

    def test_client_sent_status_is_ignored(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            '/api/v1/projects/',
            self.project_payload(status='ongoing', actual_end_date='2026-03-01'),
            format='json',
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], 'requested')
        self.assertIsNone(response.data['actual_end_date'])


class ProjectUpdateTests(ProjectApiCase):
    def test_assigned_owner_can_edit_but_gains_no_status_field(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.patch(
            f'/api/v1/projects/{self.project.pk}/',
            {'name': 'Tower A Phase 1', 'status': 'closed'}, format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['name'], 'Tower A Phase 1')
        self.assertEqual(response.data['status'], 'accepted')
        self.assertTrue(
            AuditLog.objects.filter(action='project_updated', entity_id=self.project.pk).exists()
        )

    def test_in_scope_admin_cannot_edit_an_owner_project(self):
        self.act_as(self.admin, Role.ADMIN)

        response = self.client.patch(
            f'/api/v1/projects/{self.project.pk}/', {'name': 'Nope'}, format='json',
        )

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(
            response.data['detail'], 'Only the owner running this project can edit it.',
        )

    def test_contract_amount_locks_once_work_starts(self):
        self.project.status = ProjectStatus.ONGOING
        self.project.save(update_fields=['status'])
        self.act_as(self.owner, Role.OWNER)

        response = self.client.patch(
            f'/api/v1/projects/{self.project.pk}/',
            {'contract_amount': '3000000.00'}, format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'],
            'Once work starts the contract amount changes only through approved '
            'variation orders.',
        )

    def test_client_locks_once_the_client_has_accepted(self):
        other_client = Client.objects.create(name='Second Client', user=self.other_owner)
        self.act_as(self.owner, Role.OWNER)

        open_to_change = self.client.patch(
            f'/api/v1/projects/{self.project.pk}/',
            {'client_id': other_client.pk}, format='json',
        )
        self.project.status = ProjectStatus.REQUESTED
        self.project.save(update_fields=['status'])
        editable = self.client.patch(
            f'/api/v1/projects/{self.project.pk}/',
            {'client_id': other_client.pk}, format='json',
        )

        self.assertEqual(open_to_change.status_code, 400, open_to_change.data)
        self.assertEqual(
            open_to_change.data['detail'],
            'The client cannot be changed once the client has accepted the project.',
        )
        self.assertEqual(editable.status_code, 200, editable.data)
        self.assertEqual(editable.data['client_id'], other_client.pk)

    def test_there_is_no_public_apply_variation_route(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/projects/{self.project.pk}/apply-variation/',
            {'amount_delta': '1000.00', 'days_impact': 5}, format='json',
        )

        self.assertEqual(response.status_code, 404)


class ProjectStatusTests(ProjectApiCase):
    def test_owner_moves_accepted_to_ongoing_with_audit_and_notification(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/projects/{self.project.pk}/status/',
            {'status': 'ongoing'}, format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'ongoing')
        self.assertTrue(
            AuditLog.objects.filter(
                action='project_status_changed', entity_id=self.project.pk,
            ).exists()
        )
        recipients = set(
            Notification.objects.filter(type='project_status').values_list('user_id', flat=True)
        )
        self.assertIn(self.engineer.pk, recipients)
        self.assertIn(self.client_user.pk, recipients)
        self.assertNotIn(self.owner.pk, recipients)

    def test_completing_a_project_stamps_the_actual_end_date(self):
        self.project.status = ProjectStatus.ONGOING
        self.project.save(update_fields=['status'])
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/projects/{self.project.pk}/status/',
            {'status': 'completed'}, format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertIsNotNone(response.data['actual_end_date'])

    def test_a_request_status_has_no_manual_move(self):
        self.project.status = ProjectStatus.REQUESTED
        self.project.save(update_fields=['status'])
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/projects/{self.project.pk}/status/',
            {'status': 'ongoing'}, format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'],
            'A project cannot move from Waiting for client to Ongoing.',
        )

    def test_a_site_engineer_cannot_move_the_status(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.post(
            f'/api/v1/projects/{self.project.pk}/status/',
            {'status': 'ongoing'}, format='json',
        )

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(
            response.data['detail'], 'Only the owner can move a project to Ongoing.',
        )


class AssignmentTests(ProjectApiCase):
    def test_first_response_depends_on_the_role_and_the_project_status(self):
        self.project.status = ProjectStatus.REQUESTED
        self.project.save(update_fields=['status'])
        self.act_as(self.owner, Role.OWNER)

        client_row = self.client.post(
            f'/api/v1/projects/{self.project.pk}/assignments/',
            {'user_id': self.other_owner.pk, 'role_on_project': 'owner'}, format='json',
        )
        engineer_row = self.client.post(
            f'/api/v1/projects/{self.project.pk}/assignments/',
            {'user_id': self.other_engineer.pk, 'role_on_project': 'site_engineer'},
            format='json',
        )

        self.assertEqual(client_row.status_code, 201, client_row.data)
        self.assertEqual(client_row.data['response'], 'accepted')
        self.assertEqual(engineer_row.status_code, 201, engineer_row.data)
        self.assertEqual(engineer_row.data['response'], 'not_sent')
        self.assertEqual(engineer_row.data['role_on_project'], 'site_engineer')

    def test_client_assignment_waits_and_notifies_only_when_pending(self):
        other_client_user = make_user('client2@example.com', [Role.CLIENT])
        Client.objects.create(name='Second Client', user=other_client_user)
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/projects/{self.project.pk}/assignments/',
            {'user_id': other_client_user.pk, 'role_on_project': 'client'},
            format='json',
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['response'], 'pending')
        self.assertTrue(
            Notification.objects.filter(
                user=other_client_user, type='project_request',
            ).exists()
        )
        self.assertTrue(
            AuditLog.objects.filter(action='assignment_created').exists()
        )

    def test_a_site_engineer_row_is_held_until_the_client_accepts(self):
        waiting_project = self.make_project(
            'PRJ-C', 'Tower C', status=ProjectStatus.SITE_ENGINEER_PENDING,
        )
        self.join(waiting_project, self.owner, RoleOnProject.OWNER)
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/projects/{waiting_project.pk}/assignments/',
            {'user_id': self.other_engineer.pk, 'role_on_project': 'site_engineer'},
            format='json',
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['response'], 'pending')

    def test_assignment_refusals(self):
        self.act_as(self.owner, Role.OWNER)
        url = f'/api/v1/projects/{self.project.pk}/assignments/'
        no_role = make_user('nobody@example.com', [Role.ACCOUNTANT])

        not_held = self.client.post(
            url, {'user_id': no_role.pk, 'role_on_project': 'site_engineer'},
            format='json',
        )
        duplicate = self.client.post(
            url, {'user_id': self.engineer.pk, 'role_on_project': 'site_engineer'},
            format='json',
        )

        self.assertEqual(not_held.status_code, 400, not_held.data)
        self.assertEqual(
            not_held.data['detail'],
            'The user does not hold the Site engineer / foreman role.',
        )
        self.assertEqual(duplicate.status_code, 400, duplicate.data)
        self.assertEqual(duplicate.data['detail'], 'Already on this project.')

    def test_a_declined_row_is_replaced_on_re_assign(self):
        declined_user = make_user('declined@example.com', [Role.SITE_ENGINEER])
        self.join(
            self.project, declined_user, RoleOnProject.SITE_ENGINEER,
            RequestResponse.DECLINED,
        )
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/projects/{self.project.pk}/assignments/',
            {'user_id': declined_user.pk, 'role_on_project': 'site_engineer'},
            format='json',
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(
            ProjectAssignment.objects.filter(
                project=self.project, user=declined_user,
            ).count(),
            1,
        )

    def test_client_cannot_read_the_project_team(self):
        self.act_as(self.client_user, Role.CLIENT)

        response = self.client.get(f'/api/v1/projects/{self.project.pk}/assignments/')

        self.assertEqual(response.status_code, 403, response.data)

    def test_assignments_for_a_user_are_admin_or_self_only(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        own = self.client.get(f'/api/v1/project-assignments/?user={self.engineer.pk}')
        someone_else = self.client.get(
            f'/api/v1/project-assignments/?user={self.owner.pk}'
        )

        self.act_as(self.admin, Role.ADMIN)
        anyone = self.client.get(f'/api/v1/project-assignments/?user={self.owner.pk}')

        self.assertEqual(own.status_code, 200, own.data)
        self.assertEqual([row['project_id'] for row in own.data], [self.project.pk])
        self.assertEqual(someone_else.status_code, 403, someone_else.data)
        self.assertEqual(anyone.status_code, 200, anyone.data)

    def test_admin_can_replace_a_users_assignments(self):
        target = make_user('newse@example.com', [Role.SITE_ENGINEER])
        self.act_as(self.admin, Role.ADMIN)

        response = self.client.put(
            f'/api/v1/users/{target.pk}/assignments/',
            {'assignments': [
                {'project_id': self.project.pk, 'role': 'site_engineer'},
                {'project_id': self.other_project.pk, 'role': 'site_engineer'},
            ]},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            {row['project_id'] for row in response.data},
            {self.project.pk, self.other_project.pk},
        )
        self.assertTrue(
            AuditLog.objects.filter(action='user_assignments_set').exists()
        )

    def test_replacing_assignments_needs_the_admin_role(self):
        target = make_user('newse@example.com', [Role.SITE_ENGINEER])
        self.act_as(self.owner, Role.OWNER)

        response = self.client.put(
            f'/api/v1/users/{target.pk}/assignments/',
            {'assignments': []}, format='json',
        )

        self.assertEqual(response.status_code, 403, response.data)

    def test_admin_can_unassign(self):
        row = ProjectAssignment.objects.get(project=self.project, user=self.engineer)
        self.act_as(self.admin, Role.ADMIN)

        response = self.client.delete(f'/api/v1/project-assignments/{row.pk}/')

        self.assertEqual(response.status_code, 204, response.data)
        self.assertFalse(ProjectAssignment.objects.filter(pk=row.pk).exists())
        self.assertTrue(AuditLog.objects.filter(action='assignment_removed').exists())


class RespondTests(ProjectApiCase):
    def setUp(self):
        super().setUp()
        self.project.status = ProjectStatus.REQUESTED
        self.project.save(update_fields=['status'])
        self.client_row = ProjectAssignment.objects.get(
            project=self.project, user=self.client_user,
        )
        self.client_row.response = RequestResponse.PENDING
        self.client_row.save(update_fields=['response'])
        self.engineer_row = ProjectAssignment.objects.get(
            project=self.project, user=self.engineer,
        )
        self.engineer_row.response = RequestResponse.NOT_SENT
        self.engineer_row.save(update_fields=['response'])

    def respond(self, user, role, assignment, answer, note=None):
        self.act_as(user, role)
        return self.client.post(
            f'/api/v1/project-assignments/{assignment.pk}/respond/',
            {'response': answer, 'note': note}, format='json',
        )

    def test_client_accept_sends_it_to_the_site_engineer(self):
        response = self.respond(
            self.client_user, Role.CLIENT, self.client_row, 'accepted',
        )

        self.project.refresh_from_db()
        self.engineer_row.refresh_from_db()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['response'], 'accepted')
        self.assertEqual(self.project.status, ProjectStatus.SITE_ENGINEER_PENDING)
        self.assertEqual(self.engineer_row.response, RequestResponse.PENDING)
        self.assertTrue(
            Notification.objects.filter(
                user=self.engineer, type='project_request',
            ).exists()
        )
        self.assertTrue(
            AuditLog.objects.filter(action='project_request_accepted').exists()
        )

    def test_site_engineer_accept_finishes_the_handshake(self):
        self.project.status = ProjectStatus.SITE_ENGINEER_PENDING
        self.project.save(update_fields=['status'])
        self.client_row.response = RequestResponse.ACCEPTED
        self.client_row.save(update_fields=['response'])
        self.engineer_row.response = RequestResponse.PENDING
        self.engineer_row.save(update_fields=['response'])

        response = self.respond(
            self.engineer, Role.SITE_ENGINEER, self.engineer_row, 'accepted',
        )

        self.project.refresh_from_db()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self.project.status, ProjectStatus.ACCEPTED)

    def test_client_change_request_moves_the_project_back(self):
        response = self.respond(
            self.client_user, Role.CLIENT, self.client_row,
            'changes_requested', 'Please extend the target date.',
        )

        self.project.refresh_from_db()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self.project.status, ProjectStatus.CHANGES_REQUESTED)
        self.assertEqual(response.data['note'], 'Please extend the target date.')
        self.assertTrue(
            Notification.objects.filter(
                user=self.owner, message__contains='asked for changes',
            ).exists()
        )

    def test_client_decline_is_soft_and_audited(self):
        response = self.respond(
            self.client_user, Role.CLIENT, self.client_row, 'declined', 'Too costly.',
        )

        self.project.refresh_from_db()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self.project.status, ProjectStatus.DECLINED)
        self.assertEqual(Project.objects.filter(pk=self.project.pk).count(), 1)
        self.assertTrue(
            AuditLog.objects.filter(action='project_request_declined').exists()
        )
        self.assertTrue(
            AuditLog.objects.filter(
                action='project_status_changed', entity_id=self.project.pk,
                details__to='declined',
            ).exists()
        )
        # Hidden from the owner's list afterwards.
        self.act_as(self.owner, Role.OWNER)
        self.assertEqual(self.client.get('/api/v1/projects/').data, [])

    def test_site_engineer_decline_leaves_the_status_alone(self):
        self.project.status = ProjectStatus.SITE_ENGINEER_PENDING
        self.project.save(update_fields=['status'])
        self.engineer_row.response = RequestResponse.PENDING
        self.engineer_row.save(update_fields=['response'])

        response = self.respond(
            self.engineer, Role.SITE_ENGINEER, self.engineer_row,
            'declined', 'Booked elsewhere.',
        )

        self.project.refresh_from_db()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self.project.status, ProjectStatus.SITE_ENGINEER_PENDING)
        self.assertTrue(
            Notification.objects.filter(
                user=self.owner, message__contains='Choose another site engineer',
            ).exists()
        )

    def test_only_the_assignee_can_respond(self):
        response = self.respond(
            self.other_owner, Role.OWNER, self.client_row, 'accepted',
        )

        self.assertEqual(response.status_code, 404, response.data)

    def test_response_refusals(self):
        self.engineer_row.response = RequestResponse.PENDING
        self.engineer_row.save(update_fields=['response'])
        not_pending = self.respond(
            self.engineer, Role.SITE_ENGINEER, self.engineer_row, 'pending',
        )
        no_note = self.respond(
            self.client_user, Role.CLIENT, self.client_row, 'declined',
        )
        answered = self.respond(
            self.client_user, Role.CLIENT, self.client_row, 'accepted',
        )
        already = self.respond(
            self.client_user, Role.CLIENT, self.client_row, 'accepted',
        )

        self.assertEqual(not_pending.status_code, 400, not_pending.data)
        self.assertEqual(
            not_pending.data['detail'], 'Accept, decline or ask for changes.',
        )
        self.assertEqual(no_note.status_code, 400, no_note.data)
        self.assertEqual(
            no_note.data['detail'], 'Add a note so the owner knows why.',
        )
        self.assertEqual(answered.status_code, 200, answered.data)
        self.assertEqual(already.status_code, 400, already.data)
        self.assertEqual(already.data['detail'], 'You already answered this request.')

    def test_only_a_client_can_ask_for_changes(self):
        self.project.status = ProjectStatus.SITE_ENGINEER_PENDING
        self.project.save(update_fields=['status'])
        self.engineer_row.response = RequestResponse.PENDING
        self.engineer_row.save(update_fields=['response'])

        response = self.respond(
            self.engineer, Role.SITE_ENGINEER, self.engineer_row,
            'changes_requested', 'Add a crane.',
        )

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(
            response.data['detail'], 'Only the client can ask for changes.',
        )

    def test_project_requests_lists_only_the_callers_pending_rows(self):
        self.act_as(self.client_user, Role.CLIENT)

        listing = self.client.get('/api/v1/project-requests/')

        self.assertEqual(listing.status_code, 200, listing.data)
        self.assertEqual(len(listing.data), 1)
        self.assertEqual(set(listing.data[0]), {'project', 'assignment'})
        self.assertEqual(
            listing.data[0]['assignment']['response'], 'pending',
        )
        self.assertFalse(FINANCE_KEYS - FINANCE_KEYS & set(listing.data[0]['project']))
        self.assertEqual(listing.data[0]['project']['code'], 'PRJ-A')


class ResendTests(ProjectApiCase):
    def test_owner_resends_a_change_request_back_to_the_client(self):
        self.project.status = ProjectStatus.CHANGES_REQUESTED
        self.project.save(update_fields=['status'])
        row = ProjectAssignment.objects.get(project=self.project, user=self.client_user)
        row.response = RequestResponse.CHANGES_REQUESTED
        row.note = 'Extend it.'
        row.save(update_fields=['response', 'note'])
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(f'/api/v1/projects/{self.project.pk}/resend/')

        self.project.refresh_from_db()
        row.refresh_from_db()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self.project.status, ProjectStatus.REQUESTED)
        self.assertEqual(row.response, RequestResponse.PENDING)
        self.assertIsNone(row.responded_at)
        self.assertTrue(
            AuditLog.objects.filter(action='project_request_resent').exists()
        )

    def test_resend_refusals(self):
        self.act_as(self.owner, Role.OWNER)
        wrong_status = self.client.post(f'/api/v1/projects/{self.project.pk}/resend/')

        self.project.status = ProjectStatus.CHANGES_REQUESTED
        self.project.save(update_fields=['status'])
        self.act_as(self.admin, Role.ADMIN)
        not_owner = self.client.post(f'/api/v1/projects/{self.project.pk}/resend/')

        self.assertEqual(wrong_status.status_code, 400, wrong_status.data)
        self.assertEqual(
            wrong_status.data['detail'],
            'Only a project the client asked to change is sent again.',
        )
        self.assertEqual(not_owner.status_code, 403, not_owner.data)
        self.assertEqual(
            not_owner.data['detail'],
            'Only the owner running this project can send it again.',
        )


class ClientWriteRefusalTests(ProjectApiCase):
    def test_a_client_cannot_write_anything_but_their_own_answer(self):
        self.act_as(self.client_user, Role.CLIENT)
        project = self.project
        calls = [
            ('post', '/api/v1/projects/', self.project_payload()),
            ('patch', f'/api/v1/projects/{project.pk}/', {'name': 'Nope'}),
            ('post', f'/api/v1/projects/{project.pk}/status/', {'status': 'ongoing'}),
            ('post', f'/api/v1/projects/{project.pk}/assignments/',
             {'user_id': self.engineer.pk, 'role_on_project': 'site_engineer'}),
            ('post', f'/api/v1/projects/{project.pk}/categories/', {'name': 'Hack'}),
            ('patch', f'/api/v1/categories/{self.category.pk}/', {'name': 'Hack'}),
            ('delete', f'/api/v1/categories/{self.category.pk}/', None),
            ('post', '/api/v1/todos/',
             {'category_id': self.category.pk, 'title': 'Hack',
              'start_date': '2026-01-05', 'end_date': '2026-01-06'}),
            ('patch', f'/api/v1/todos/{self.todo.pk}/', {'title': 'Hack'}),
            ('post', f'/api/v1/todos/{self.todo.pk}/done/', {'done': True}),
            ('post', f'/api/v1/todos/{self.todo.pk}/verify/', None),
            ('post', f'/api/v1/todos/{self.todo.pk}/unverify/', {'reason': 'x'}),
        ]
        for method, url, payload in calls:
            call = getattr(self.client, method)
            response = (
                call(url, payload, format='json') if payload is not None else call(url)
            )
            self.assertIn(
                response.status_code, (403, 404),
                f'{method.upper()} {url} -> {response.status_code} {response.data}',
            )


class RoleMatrixTests(ProjectApiCase):
    def test_a_site_engineer_cannot_verify_or_unverify(self):
        self.todo.is_done = True
        self.todo.save(update_fields=['is_done'])
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.post(f'/api/v1/todos/{self.todo.pk}/verify/')

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(
            response.data['detail'],
            'Only the owner running this project can verify to-dos.',
        )

    def test_an_admin_cannot_write_the_schedule(self):
        self.act_as(self.admin, Role.ADMIN)

        response = self.client.post(
            f'/api/v1/projects/{self.project.pk}/categories/',
            {'name': 'Admin category'}, format='json',
        )

        self.assertEqual(response.status_code, 403, response.data)

    def test_an_unassigned_owner_has_no_scope_at_all(self):
        self.act_as(self.other_owner, Role.OWNER)

        self.assertEqual(
            self.client.get(f'/api/v1/projects/{self.project.pk}/').status_code, 404,
        )
        self.assertEqual(
            self.client.post(f'/api/v1/todos/{self.todo.pk}/verify/').status_code, 404,
        )

    def test_the_active_role_header_decides_rights(self):
        dual = make_user('dual@example.com', [Role.OWNER, Role.SITE_ENGINEER])
        Assignment = ProjectAssignment
        Assignment.objects.create(
            project=self.project, user=dual,
            role_on_project=RoleOnProject.SITE_ENGINEER,
            response=RequestResponse.ACCEPTED,
        )
        self.todo.is_done = True
        self.todo.save(update_fields=['is_done'])

        self.act_as(dual, Role.SITE_ENGINEER)
        as_engineer_read = self.client.get(f'/api/v1/projects/{self.project.pk}/')
        as_engineer_verify = self.client.post(f'/api/v1/todos/{self.todo.pk}/verify/')

        self.act_as(dual, Role.OWNER)
        as_owner_read = self.client.get(f'/api/v1/projects/{self.project.pk}/')

        self.assertEqual(as_engineer_read.status_code, 200)
        self.assertFalse(FINANCE_KEYS & set(as_engineer_read.data))
        self.assertEqual(as_engineer_verify.status_code, 403)
        self.assertEqual(as_owner_read.status_code, 404)


class CategoryTests(ProjectApiCase):
    def test_owner_creates_and_lists_categories_by_sort_order(self):
        self.act_as(self.owner, Role.OWNER)
        second = Category.objects.create(
            project=self.project, name='Finishing', sort_order=2,
        )

        created = self.client.post(
            f'/api/v1/projects/{self.project.pk}/categories/',
            {'name': 'Structural', 'budget': '300000.00', 'sort_order': 1},
            format='json',
        )
        listing = self.client.get(f'/api/v1/projects/{self.project.pk}/categories/')

        self.assertEqual(created.status_code, 201, created.data)
        self.assertEqual(
            set(created.data),
            {'id', 'project_id', 'name', 'budget', 'weight', 'sort_order',
             'created_at', 'updated_at'},
        )
        self.assertEqual(
            [row['name'] for row in listing.data],
            ['Siteworks', 'Structural', 'Finishing'],
        )
        self.assertEqual(second.project_id, self.project.pk)

    def test_category_refusals(self):
        self.act_as(self.owner, Role.OWNER)
        url = f'/api/v1/projects/{self.project.pk}/categories/'
        cases = [
            ({'name': '  '}, 'Enter a category name.'),
            ({'name': 'Steel', 'budget': '-5'}, 'Budget cannot be negative.'),
            ({'name': 'Steel', 'budget': '900000'},
             'Total category budgets (₱1,300,000) would exceed the contract '
             'amount (₱1,000,000).'),
        ]
        for payload, message in cases:
            response = self.client.post(url, payload, format='json')

            self.assertEqual(response.status_code, 400, (payload, response.data))
            self.assertEqual(response.data['detail'], message)

    def test_category_project_cannot_be_moved_by_the_body(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.patch(
            f'/api/v1/categories/{self.category.pk}/',
            {'name': 'Siteworks 2', 'project_id': self.other_project.pk},
            format='json',
        )

        self.category.refresh_from_db()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['name'], 'Siteworks 2')
        self.assertEqual(self.category.project_id, self.project.pk)

    def test_category_with_a_verified_todo_cannot_be_deleted(self):
        self.todo.is_done = True
        self.todo.is_verified = True
        self.todo.save(update_fields=['is_done', 'is_verified'])
        self.act_as(self.owner, Role.OWNER)

        refused = self.client.delete(f'/api/v1/categories/{self.category.pk}/')

        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(
            refused.data['detail'],
            'This category has verified to-dos and cannot be deleted.',
        )
        self.assertTrue(Category.objects.filter(pk=self.category.pk).exists())


class CategoryWeightTests(ProjectApiCase):
    def weights(self, user, role):
        self.act_as(user, role)
        rows = self.client.get(f'/api/v1/projects/{self.project.pk}/categories/').data
        return {row['id']: row['weight'] for row in rows}

    def test_weights_follow_the_budget_share_for_every_role(self):
        second = Category.objects.create(
            project=self.project, name='Finishing', sort_order=2,
            budget=Decimal('600000.00'),
        )

        for user, role in (
            (self.owner, Role.OWNER),
            (self.accountant, Role.ACCOUNTANT),
            (self.admin, Role.ADMIN),
            (self.engineer, Role.SITE_ENGINEER),
            (self.client_user, Role.CLIENT),
        ):
            weights = self.weights(user, role)
            self.assertAlmostEqual(weights[self.category.pk], 0.4, places=6)
            self.assertAlmostEqual(weights[second.pk], 0.6, places=6)

    def test_equal_weights_when_a_budget_is_missing(self):
        second = Category.objects.create(
            project=self.project, name='Finishing', sort_order=2,
        )

        weights = self.weights(self.engineer, Role.SITE_ENGINEER)

        self.assertAlmostEqual(weights[self.category.pk], 0.5, places=6)
        self.assertAlmostEqual(weights[second.pk], 0.5, places=6)

    def test_budget_is_finance_only_but_weight_always_ships(self):
        for user, role in (
            (self.admin, Role.ADMIN),
            (self.engineer, Role.SITE_ENGINEER),
            (self.client_user, Role.CLIENT),
        ):
            self.act_as(user, role)
            row = self.client.get(
                f'/api/v1/projects/{self.project.pk}/categories/'
            ).data[0]
            self.assertNotIn('budget', row, row)
            self.assertIn('weight', row, row)

        self.act_as(self.owner, Role.OWNER)
        row = self.client.get(
            f'/api/v1/projects/{self.project.pk}/categories/'
        ).data[0]
        self.assertEqual(Decimal(row['budget']), Decimal('400000.00'))


class TodoTests(ProjectApiCase):
    def test_owner_creates_a_todo_with_server_only_flags_false(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            '/api/v1/todos/',
            {'category_id': self.category.pk, 'title': ' Pour slab ',
             'start_date': '2026-02-01', 'end_date': '2026-02-10',
             'is_done': True, 'is_verified': True},
            format='json',
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(
            set(response.data),
            {'id', 'category_id', 'title', 'start_date', 'end_date', 'is_done',
             'done_by', 'done_at', 'is_verified', 'verified_by', 'verified_at',
             'daily_report_id', 'created_at', 'updated_at'},
        )
        self.assertEqual(response.data['title'], 'Pour slab')
        self.assertFalse(response.data['is_done'])
        self.assertFalse(response.data['is_verified'])

    def test_todo_refusals(self):
        self.act_as(self.owner, Role.OWNER)
        cases = [
            ({'title': ' ', 'start_date': '2026-02-01', 'end_date': '2026-02-02'},
             'Enter a to-do title.'),
            ({'title': 'Pour', 'start_date': None, 'end_date': None},
             'Choose start and end dates.'),
            ({'title': 'Pour', 'start_date': '2026-02-05', 'end_date': '2026-02-01'},
             'End date must be on or after the start date.'),
            ({'title': 'Pour', 'start_date': '2025-12-01', 'end_date': '2026-02-01'},
             'Dates must fall within the project schedule '
             '(2026-01-01 to 2026-06-30).'),
        ]
        for payload, message in cases:
            response = self.client.post(
                '/api/v1/todos/', {'category_id': self.category.pk, **payload},
                format='json',
            )

            self.assertEqual(response.status_code, 400, (payload, response.data))
            self.assertEqual(response.data['detail'], message)

    def test_a_todo_cannot_be_moved_to_another_projects_category(self):
        foreign = Category.objects.create(project=self.other_project, name='Other')
        self.act_as(self.owner, Role.OWNER)

        response = self.client.patch(
            f'/api/v1/todos/{self.todo.pk}/', {'category_id': foreign.pk},
            format='json',
        )

        self.todo.refresh_from_db()
        self.assertEqual(response.status_code, 404, response.data)
        self.assertEqual(self.todo.category_id, self.category.pk)

    def test_todo_update_ignores_done_and_verify_fields(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.patch(
            f'/api/v1/todos/{self.todo.pk}/',
            {'title': 'Excavate footing', 'is_done': True, 'is_verified': True},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['title'], 'Excavate footing')
        self.assertFalse(response.data['is_done'])
        self.assertFalse(response.data['is_verified'])

    def test_marking_done_stamps_the_actor_and_notifies_the_owner(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.post(
            f'/api/v1/todos/{self.todo.pk}/done/', {'done': True}, format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data['is_done'])
        self.assertEqual(response.data['done_by'], self.engineer.pk)
        self.assertIsNotNone(response.data['done_at'])
        self.assertTrue(AuditLog.objects.filter(action='todo_marked_done').exists())
        self.assertTrue(
            Notification.objects.filter(user=self.owner, type='todo_done').exists()
        )

    def test_un_done_is_refused_while_verified(self):
        self.todo.is_done = True
        self.todo.is_verified = True
        self.todo.save(update_fields=['is_done', 'is_verified'])
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.post(
            f'/api/v1/todos/{self.todo.pk}/done/', {'done': False}, format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'],
            'This to-do is verified. The owner must un-verify it first.',
        )

    def test_owner_verifies_and_unverifies_with_reasons_audited(self):
        self.todo.is_done = True
        self.todo.done_by = self.engineer
        self.todo.save(update_fields=['is_done', 'done_by'])
        self.act_as(self.owner, Role.OWNER)

        verified = self.client.post(f'/api/v1/todos/{self.todo.pk}/verify/')
        again = self.client.post(f'/api/v1/todos/{self.todo.pk}/verify/')
        no_reason = self.client.post(
            f'/api/v1/todos/{self.todo.pk}/unverify/', {'reason': '  '},
            format='json',
        )
        unverified = self.client.post(
            f'/api/v1/todos/{self.todo.pk}/unverify/',
            {'reason': 'Photo shows rework.'}, format='json',
        )

        self.assertEqual(verified.status_code, 200, verified.data)
        self.assertTrue(verified.data['is_verified'])
        self.assertEqual(verified.data['verified_by'], self.owner.pk)
        self.assertEqual(again.status_code, 400, again.data)
        self.assertEqual(again.data['detail'], 'This to-do is already verified.')
        self.assertEqual(no_reason.status_code, 400, no_reason.data)
        self.assertEqual(
            no_reason.data['detail'], 'Enter a reason for un-verifying.',
        )
        self.assertEqual(unverified.status_code, 200, unverified.data)
        self.assertFalse(unverified.data['is_verified'])
        self.assertTrue(
            AuditLog.objects.filter(
                action='todo_unverified', details__reason='Photo shows rework.',
            ).exists()
        )

    def test_verifying_a_todo_that_is_not_done_is_refused(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(f'/api/v1/todos/{self.todo.pk}/verify/')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'], 'Only to-dos marked done can be verified.',
        )

    def test_owner_self_verify_is_allowed_and_audited(self):
        self.act_as(self.owner, Role.OWNER)

        self.client.post(
            f'/api/v1/todos/{self.todo.pk}/done/', {'done': True}, format='json',
        )
        verified = self.client.post(f'/api/v1/todos/{self.todo.pk}/verify/')

        self.assertEqual(verified.status_code, 200, verified.data)
        self.assertEqual(
            list(
                AuditLog.objects.filter(entity_id=self.todo.pk).values_list(
                    'action', flat=True,
                )
            ).count('todo_marked_done'),
            1,
        )
        self.assertTrue(AuditLog.objects.filter(action='todo_verified').exists())

    def test_a_verified_todo_cannot_be_deleted(self):
        self.todo.is_verified = True
        self.todo.save(update_fields=['is_verified'])
        self.act_as(self.owner, Role.OWNER)

        response = self.client.delete(f'/api/v1/todos/{self.todo.pk}/')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'],
            'A verified to-do cannot be deleted. Un-verify it first.',
        )


class ClientListTests(ProjectApiCase):
    def test_staff_can_list_clients_and_the_client_cannot(self):
        self.act_as(self.owner, Role.OWNER)
        staff = self.client.get('/api/v1/clients/')

        self.act_as(self.client_user, Role.CLIENT)
        portal = self.client.get('/api/v1/clients/')

        self.assertEqual(staff.status_code, 200, staff.data)
        self.assertEqual(
            set(staff.data[0]),
            {'id', 'name', 'contact_person', 'email', 'phone', 'address',
             'user_id', 'created_at', 'updated_at'},
        )
        self.assertEqual(portal.status_code, 403, portal.data)


class ClientWriteTests(ProjectApiCase):
    """`clients/` writes (task 5.3): owner/admin only, one login per client.

    Closes the Phase 2.3 limit where `ClientRepository` could not leave mock
    mode because the route only read. A client role may still only read its
    own portal data; contact details stay staff-only (no new rule invented).
    """

    def payload(self, **overrides):
        body = {
            'name': 'Batangas Agri Co.',
            'contact_person': 'Rosa Lim',
            'email': 'rosa@example.ph',
            'phone': '+63 917 000 0000',
            'address': 'Lipa City',
        }
        body.update(overrides)
        return body

    def client_row_keys(self):
        return {
            'id', 'name', 'contact_person', 'email', 'phone', 'address',
            'user_id', 'created_at', 'updated_at',
        }

    # --- create ---

    def test_owner_and_admin_create_a_client(self):
        for user, role in ((self.owner, Role.OWNER), (self.admin, Role.ADMIN)):
            self.act_as(user, role)
            response = self.client.post(
                '/api/v1/clients/',
                self.payload(name=f'{role.title()} Client'),
                format='json',
            )

            self.assertEqual(response.status_code, 201, response.data)
            self.assertEqual(set(response.data), self.client_row_keys())
            self.assertEqual(response.data['name'], f'{role.title()} Client')
            self.assertIsNone(response.data['user_id'])

        self.assertEqual(Client.objects.filter(name__startswith='Owner Client').count(), 1)
        actions = set(AuditLog.objects.filter(entity='client').values_list('action', flat=True))
        self.assertEqual(actions, {'client_created'})

    def test_create_audit_carries_the_name_only(self):
        self.act_as(self.owner, Role.OWNER)

        self.client.post('/api/v1/clients/', self.payload(), format='json')

        row = AuditLog.objects.get(action='client_created')
        self.assertEqual(row.entity, 'client')
        self.assertEqual(row.details, {'name': 'Batangas Agri Co.'})

    def test_read_only_roles_cannot_write_clients(self):
        for user, role in (
            (self.accountant, Role.ACCOUNTANT),
            (self.engineer, Role.SITE_ENGINEER),
            (self.client_user, Role.CLIENT),
        ):
            self.act_as(user, role)
            created = self.client.post('/api/v1/clients/', self.payload(), format='json')
            renamed = self.client.patch(
                f'/api/v1/clients/{self.client_record.pk}/',
                {'name': 'Hijacked'},
                format='json',
            )
            linked = self.client.post(
                f'/api/v1/clients/{self.client_record.pk}/link-user/',
                {'user_id': self.client_user.pk},
                format='json',
            )

            for response in (created, renamed, linked):
                self.assertEqual(response.status_code, 403, response.data)
                self.assertEqual(
                    response.data['detail'],
                    'Project Manager or Admin role required to change this.',
                )
        self.assertFalse(Client.objects.filter(name='Batangas Agri Co.').exists())

    def test_create_refuses_blank_and_duplicate_names(self):
        self.act_as(self.owner, Role.OWNER)

        blank = self.client.post('/api/v1/clients/', self.payload(name='   '), format='json')
        duplicate = self.client.post(
            '/api/v1/clients/', self.payload(name='acme holdings'), format='json',
        )

        self.assertEqual(blank.status_code, 400, blank.data)
        self.assertEqual(blank.data['detail'], 'Enter the client name.')
        self.assertEqual(duplicate.status_code, 400, duplicate.data)
        self.assertEqual(
            duplicate.data['detail'], 'A client with this name already exists.',
        )

    def test_create_refuses_a_bad_email(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            '/api/v1/clients/', self.payload(email='not-an-email'), format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], 'Enter a valid email address.')

    def test_create_ignores_the_user_link_and_ids(self):
        """A login is linked by its own route; `id`/timestamps stay server-owned."""
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            '/api/v1/clients/',
            self.payload(id=999, created_at='2020-01-01T00:00:00Z'),
            format='json',
        )
        linked = self.client.post(
            '/api/v1/clients/',
            self.payload(name='Other Co.', user_id=self.client_user.pk),
            format='json',
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertNotEqual(response.data['id'], 999)
        self.assertEqual(linked.status_code, 400, linked.data)
        self.assertEqual(
            linked.data['detail'], 'Link a portal login with the link route.',
        )

    # --- update ---

    def test_update_renames_and_keeps_the_link(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.patch(
            f'/api/v1/clients/{self.client_record.pk}/',
            {'contact_person': 'Jo Cruz', 'email': ''},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['contact_person'], 'Jo Cruz')
        self.assertEqual(response.data['email'], '')
        self.assertEqual(response.data['user_id'], self.client_user.pk)
        self.assertTrue(
            AuditLog.objects.filter(action='client_updated', entity='client').exists()
        )
        self.assertEqual(
            AuditLog.objects.get(action='client_updated').details,
            {'name': 'Acme Holdings'},
        )

    def test_update_refuses_a_name_another_client_holds(self):
        Client.objects.create(name='Second Client')
        self.act_as(self.owner, Role.OWNER)

        response = self.client.patch(
            f'/api/v1/clients/{self.client_record.pk}/',
            {'name': 'second client'},
            format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'], 'A client with this name already exists.',
        )

    def test_update_does_not_move_the_link(self):
        other = make_user('link2@example.com', [Role.CLIENT])
        self.act_as(self.owner, Role.OWNER)

        response = self.client.patch(
            f'/api/v1/clients/{self.client_record.pk}/',
            {'user_id': other.pk},
            format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'], 'Link a portal login with the link route.',
        )
        self.client_record.refresh_from_db()
        self.assertEqual(self.client_record.user_id, self.client_user.pk)

    # --- link / unlink ---

    def test_link_attaches_a_client_role_login(self):
        email_only = make_user('portal@example.com', [Role.CLIENT])
        record = Client.objects.create(name='No Login Yet')
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/clients/{record.pk}/link-user/',
            {'user_id': email_only.pk},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['user_id'], email_only.pk)
        audit = AuditLog.objects.get(action='client_user_linked')
        self.assertEqual(
            audit.details, {'name': 'No Login Yet', 'user': email_only.pk},
        )

    def test_link_refuses_a_user_without_the_client_role(self):
        record = Client.objects.create(name='No Login Yet')
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/clients/{record.pk}/link-user/',
            {'user_id': self.engineer.pk},
            format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'], 'The user does not hold the Client role.',
        )
        record.refresh_from_db()
        self.assertIsNone(record.user_id)

    def test_link_refuses_a_client_that_already_has_a_login(self):
        second = make_user('portal@example.com', [Role.CLIENT])
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/clients/{self.client_record.pk}/link-user/',
            {'user_id': second.pk},
            format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'], 'That client already has a portal login linked.',
        )
        self.client_record.refresh_from_db()
        self.assertEqual(self.client_record.user_id, self.client_user.pk)

    def test_link_moves_a_login_off_its_previous_client(self):
        record = Client.objects.create(name='New Home')
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/clients/{record.pk}/link-user/',
            {'user_id': self.client_user.pk},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.client_record.refresh_from_db()
        record.refresh_from_db()
        self.assertIsNone(self.client_record.user_id)
        self.assertEqual(record.user_id, self.client_user.pk)

    def test_link_refuses_a_missing_or_unknown_user(self):
        self.act_as(self.owner, Role.OWNER)

        missing = self.client.post(
            f'/api/v1/clients/{self.client_record.pk}/link-user/', {}, format='json',
        )
        unknown = self.client.post(
            f'/api/v1/clients/{self.client_record.pk}/link-user/',
            {'user_id': 12345},
            format='json',
        )

        self.assertEqual(missing.status_code, 400, missing.data)
        self.assertEqual(missing.data['detail'], 'Choose the user to link.')
        self.assertEqual(unknown.status_code, 400, unknown.data)
        self.assertEqual(unknown.data['detail'], 'That user does not exist.')

    def test_unlink_clears_the_login(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/clients/{self.client_record.pk}/unlink-user/', format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertIsNone(response.data['user_id'])
        self.client_record.refresh_from_db()
        self.assertIsNone(self.client_record.user_id)
        self.assertEqual(
            AuditLog.objects.get(action='client_user_unlinked').details,
            {'name': 'Acme Holdings', 'user': self.client_user.pk},
        )

    def test_unlink_is_a_no_op_for_a_client_without_a_login(self):
        record = Client.objects.create(name='No Login Yet')
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/clients/{record.pk}/unlink-user/', format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(
            AuditLog.objects.filter(action='client_user_unlinked').exists()
        )

    def test_link_race_on_the_unique_login_becomes_a_refusal(self):
        """Two requests racing past the pre-check hit the `OneToOne` index."""
        record = Client.objects.create(name='No Login Yet')
        self.act_as(self.owner, Role.OWNER)

        with mock.patch.object(
            Client, 'save', side_effect=IntegrityError('client_record_id_key'),
        ):
            response = self.client.post(
                f'/api/v1/clients/{record.pk}/link-user/',
                {'user_id': self.client_user.pk},
                format='json',
            )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'], 'That client already has a portal login linked.',
        )

    # --- no hard delete, scope ---

    def test_clients_cannot_be_deleted(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.delete(f'/api/v1/clients/{self.client_record.pk}/')

        self.assertEqual(response.status_code, 405, response.data)
        self.assertTrue(Client.objects.filter(pk=self.client_record.pk).exists())

    def test_a_write_is_404_for_a_client_that_does_not_exist(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.patch(
            '/api/v1/clients/9999/', {'name': 'Ghost'}, format='json',
        )

        self.assertEqual(response.status_code, 404, response.data)


class QueryFilterValidationTests(ProjectApiCase):
    """A junk `?filter=` value is a `400`, never a server error (review 2.1 minor 3)."""

    def test_a_non_numeric_project_filter_is_refused(self):
        self.act_as(self.admin, Role.ADMIN)

        response = self.client.get('/api/v1/project-assignments/?project=abc')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'], 'The project filter must be a number.',
        )

    def test_a_non_numeric_user_filter_is_refused(self):
        self.act_as(self.admin, Role.ADMIN)

        response = self.client.get('/api/v1/project-assignments/?user=abc')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'], 'The user filter must be a number.',
        )


class UniqueRaceTests(ProjectApiCase):
    """Two requests racing past the pre-check hit the unique index (review 2.1 minor 2).

    The pre-check is patched to "not found", so the insert loses the race and the
    database answers. The service must turn that into the mock's `400`, and must
    not swallow an `IntegrityError` that is not the expected unique index.
    """

    def test_project_code_race_becomes_a_refusal(self):
        self.act_as(self.owner, Role.OWNER)

        with mock.patch('apps.projects.services._code_taken', return_value=False):
            response = self.client.post(
                '/api/v1/projects/', self.project_payload(code='PRJ-A'),
                format='json',
            )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'], 'Another project already uses this code.',
        )
        self.assertFalse(Project.objects.filter(name='Warehouse C').exists())

    def test_duplicate_assignment_race_becomes_a_refusal(self):
        self.act_as(self.owner, Role.OWNER)

        with mock.patch(
            'apps.projects.services._assignment_exists', return_value=False,
        ):
            response = self.client.post(
                f'/api/v1/projects/{self.project.pk}/assignments/',
                {'user_id': self.engineer.pk, 'role_on_project': 'site_engineer'},
                format='json',
            )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], 'Already on this project.')

    def test_an_unexpected_integrity_error_is_still_raised(self):
        self.act_as(self.owner, Role.OWNER)

        with mock.patch('apps.projects.services._code_taken', return_value=False), \
                mock.patch.object(Project, 'save', side_effect=IntegrityError('boom')), \
                self.assertRaises(IntegrityError):
            self.client.post(
                '/api/v1/projects/', self.project_payload(), format='json',
            )


class UnassignAuditTests(ProjectApiCase):
    """`assignment_removed` names the assignment row, not the member (review 2.1 minor 4)."""

    def test_the_audit_row_carries_the_assignment_id_and_the_member(self):
        row = ProjectAssignment.objects.get(project=self.project, user=self.engineer)
        self.act_as(self.owner, Role.OWNER)

        response = self.client.delete(f'/api/v1/project-assignments/{row.pk}/')

        self.assertEqual(response.status_code, 204, response.data)
        audit = AuditLog.objects.get(action='assignment_removed')
        self.assertEqual(audit.entity, 'project_assignment')
        self.assertEqual(audit.entity_id, row.pk)
        self.assertEqual(audit.details['user'], self.engineer.pk)


class NonFiniteDecimalTests(ProjectApiCase):
    """`NaN`/`Infinity` in an amount or a budget is refused, never written.

    Python's `json.loads` (DRF's JSONParser) accepts the bare literals `NaN`,
    `Infinity` and `-Infinity`, and `Decimal` parses them too, so the first
    `<`/`<=` comparison raised `InvalidOperation` — a 500 where the contract
    asks for a `400`. `rules.as_decimal` now refuses every non-finite value.
    """

    NON_FINITE = ('NaN', 'sNaN', 'Infinity', '-Infinity')

    def test_as_decimal_refuses_every_non_finite_form(self):
        from . import rules

        for value in self.NON_FINITE + (
            'inf', '-inf', 'nan', float('nan'), float('inf'), float('-inf'),
        ):
            with self.subTest(value=value):
                self.assertIsNone(rules.as_decimal(value))

        for value in ('12.5', 12.5, 0, '0'):
            with self.subTest(finite=value):
                self.assertIsNotNone(rules.as_decimal(value))

    def test_a_non_finite_create_is_a_400_and_writes_nothing(self):
        self.act_as(self.owner, Role.OWNER)
        cases = (
            ('contract_amount', 'Enter the contract amount.'),
            ('down_payment_pct', 'Enter the down payment.'),
            ('retention_pct', 'Enter the retention.'),
        )
        for value in self.NON_FINITE:
            for field, expected in cases:
                with self.subTest(value=value, field=field):
                    response = self.client.post(
                        '/api/v1/projects/',
                        self.project_payload(**{field: value}), format='json',
                    )

                    self.assertEqual(response.status_code, 400, response.data)
                    self.assertEqual(response.data['detail'], expected)
        self.assertEqual(Project.objects.count(), 2)
        self.assertFalse(Project.objects.filter(code='PRJ-C1').exists())

    def test_a_non_finite_edit_is_a_400_and_leaves_the_row_alone(self):
        self.act_as(self.owner, Role.OWNER)
        audit_rows = AuditLog.objects.count()
        for value in self.NON_FINITE:
            with self.subTest(value=value):
                response = self.client.patch(
                    f'/api/v1/projects/{self.project.pk}/',
                    {'contract_amount': value}, format='json',
                )

                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(
                    response.data['detail'], 'Enter the contract amount.',
                )
        self.project.refresh_from_db()
        self.assertEqual(self.project.contract_amount, Decimal('1000000.00'))
        self.assertEqual(AuditLog.objects.count(), audit_rows)

    def test_a_non_finite_category_budget_is_a_400_and_writes_nothing(self):
        self.act_as(self.owner, Role.OWNER)
        for value in self.NON_FINITE:
            with self.subTest(value=value):
                created = self.client.post(
                    f'/api/v1/projects/{self.project.pk}/categories/',
                    {'name': 'Steel', 'budget': value}, format='json',
                )
                edited = self.client.patch(
                    f'/api/v1/categories/{self.category.pk}/',
                    {'budget': value}, format='json',
                )

                self.assertEqual(created.status_code, 400, created.data)
                self.assertEqual(created.data['detail'], 'Budget cannot be negative.')
                self.assertEqual(edited.status_code, 400, edited.data)
                self.assertEqual(edited.data['detail'], 'Budget cannot be negative.')
        self.assertEqual(Category.objects.count(), 1)
        self.category.refresh_from_db()
        self.assertEqual(self.category.budget, Decimal('400000.00'))

    def test_json_nan_and_infinity_literals_are_a_400_not_a_500(self):
        """A bare `NaN`/`Infinity` literal is a 400 and never a 500.

        DRF's JSONParser refuses the raw literals itself ("Out of range float
        values are not JSON compliant"), so only the status and the empty write
        set are asserted here; the refusal texts are covered by the string and
        float cases above.
        """
        self.act_as(self.owner, Role.OWNER)
        project_case = (
            '{"code": "PRJ-N1", "name": "Non-finite",'
            ' "contract_amount": %s, "down_payment_pct": "10.00",'
            ' "retention_pct": "5.00", "start_date": "2026-02-01",'
            ' "target_end_date": "2026-08-31", "client_id": %d}'
        )
        for literal in ('NaN', 'Infinity', '-Infinity'):
            with self.subTest(literal=literal):
                response = self.client.post(
                    '/api/v1/projects/',
                    project_case % (literal, self.client_record.pk),
                    content_type='application/json',
                )

                self.assertEqual(response.status_code, 400, response.data)
        category_case = (
            '{"name": "Steel", "budget": %s}'
        )
        for literal in ('NaN', 'Infinity', '-Infinity'):
            with self.subTest(budget=literal):
                response = self.client.post(
                    f'/api/v1/projects/{self.project.pk}/categories/',
                    category_case % literal,
                    content_type='application/json',
                )

                self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(Project.objects.count(), 2)
        self.assertEqual(Category.objects.count(), 1)
