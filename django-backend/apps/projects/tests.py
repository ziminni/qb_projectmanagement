"""Tests for the Phase 2 project domain models (clients, WBS, assignments)."""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

from decimal import Decimal

from django.db import IntegrityError
from django.test import TestCase

from ..users.models import Role
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


def make_project(code='PRJ-100', name='Tower One', **extra):
    """Create a project on the Flutter shape with the minimum required data."""
    return Project.objects.create(code=code, name=name, **extra)


class ClientTests(TestCase):
    def test_client_links_an_optional_portal_user(self):
        user = make_user('elena@example.com', [Role.CLIENT])

        client = Client.objects.create(name='Acme Holdings', user=user)
        unnamed = Client.objects.create(name='No Login Yet')

        self.assertEqual(client.user_id, user.pk)
        self.assertIsNone(unnamed.user_id)
        self.assertEqual(str(client), 'Acme Holdings')

    def test_a_portal_user_links_to_at_most_one_client(self):
        user = make_user('elena@example.com', [Role.CLIENT])
        Client.objects.create(name='Acme Holdings', user=user)

        with self.assertRaises(IntegrityError):
            Client.objects.create(name='Second Client', user=user)


class ProjectModelTests(TestCase):
    def test_new_project_waits_for_the_client(self):
        project = make_project()

        self.assertEqual(project.status, ProjectStatus.REQUESTED)
        self.assertEqual(project.contract_amount, Decimal('0.00'))
        self.assertIsNone(project.actual_end_date)

    def test_project_code_is_unique_case_insensitively(self):
        make_project(code='PRJ-100')

        with self.assertRaises(IntegrityError):
            make_project(code='prj-100')

    def test_finance_placeholders_default_to_zero(self):
        project = make_project()

        self.assertEqual(project.down_payment_pct, Decimal('0.00'))
        self.assertEqual(project.retention_pct, Decimal('0.00'))
        self.assertEqual(project.contract_amount, Decimal('0.00'))


class AssignmentModelTests(TestCase):
    def test_one_row_per_user_and_role_on_a_project(self):
        project = make_project()
        user = make_user('ramon@example.com', [Role.OWNER])
        ProjectAssignment.objects.create(
            project=project, user=user, role_on_project=RoleOnProject.OWNER,
            response=RequestResponse.ACCEPTED,
        )

        with self.assertRaises(IntegrityError):
            ProjectAssignment.objects.create(
                project=project, user=user,
                role_on_project=RoleOnProject.OWNER,
                response=RequestResponse.PENDING,
            )

    def test_only_accepted_assignments_are_active(self):
        project = make_project()
        user = make_user('ramon@example.com', [Role.OWNER])

        waiting = ProjectAssignment.objects.create(
            project=project, user=user, role_on_project=RoleOnProject.OWNER,
            response=RequestResponse.PENDING,
        )
        joined = ProjectAssignment.objects.create(
            project=project, user=user,
            role_on_project=RoleOnProject.SITE_ENGINEER,
            response=RequestResponse.ACCEPTED,
        )

        self.assertFalse(waiting.is_active)
        self.assertTrue(joined.is_active)


class WbsModelTests(TestCase):
    def test_category_budget_is_optional_and_ordered(self):
        project = make_project()
        Category.objects.create(project=project, name='Finishing', sort_order=2)
        first = Category.objects.create(
            project=project, name='Siteworks', sort_order=1,
            budget=Decimal('500000.00'),
        )

        self.assertEqual(list(project.categories.all())[0], first)
        self.assertIsNone(project.categories.get(name='Finishing').budget)

    def test_a_todo_starts_open_and_unverified(self):
        project = make_project()
        category = Category.objects.create(project=project, name='Siteworks')
        todo = Todo.objects.create(
            category=category, title='Excavate',
            start_date='2026-01-05', end_date='2026-01-10',
        )

        self.assertFalse(todo.is_done)
        self.assertFalse(todo.is_verified)
        self.assertIsNone(todo.daily_report_id)
        self.assertEqual(str(todo), 'Excavate')

    def test_deleting_a_category_deletes_its_todos(self):
        project = make_project()
        category = Category.objects.create(project=project, name='Siteworks')
        Todo.objects.create(
            category=category, title='Excavate',
            start_date='2026-01-05', end_date='2026-01-10',
        )

        category.delete()

        self.assertEqual(Todo.objects.count(), 0)
