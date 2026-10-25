"""Tests for the projects, contracts, phases and timeline domain."""

from datetime import timedelta

from django.core.exceptions import ValidationError
from django.test import TestCase
from django.utils import timezone

from .models import (
    Contract,
    Milestone,
    PhaseStatus,
    Project,
    ProjectPhase,
    ProjectStatus,
    Site,
)
from .serializers import ProjectPhaseSerializer, ProjectSerializer


class ProjectDomainTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.site = Site.objects.create(code='SITE-001', name='Tagaytay Ridge')

    def make_project(self, **overrides):
        defaults = {
            'code': 'PRJ-001',
            'name': 'Ridge Villa',
            'site': self.site,
            'status': ProjectStatus.IN_PROGRESS,
        }
        defaults.update(overrides)
        return Project.objects.create(**defaults)

    def test_project_str_and_site_relation(self):
        project = self.make_project()

        self.assertEqual(str(project), 'PRJ-001 — Ridge Villa')
        self.assertEqual(self.site.projects.count(), 1)

    def test_is_overdue_true_when_target_passed_and_incomplete(self):
        project = self.make_project(
            target_end_date=timezone.localdate() - timedelta(days=1),
        )

        self.assertTrue(project.is_overdue)

    def test_is_overdue_false_when_completed_or_undated(self):
        completed = self.make_project(
            code='PRJ-002',
            status=ProjectStatus.COMPLETED,
            target_end_date=timezone.localdate() - timedelta(days=5),
        )
        undated = self.make_project(code='PRJ-003')

        self.assertFalse(completed.is_overdue)
        self.assertFalse(undated.is_overdue)

    def test_contract_amount_and_retention(self):
        project = self.make_project()
        contract = Contract.objects.create(
            project=project,
            contract_no='CT-2024-001',
            client_name='ACME Holdings',
            amount=1500000,
            retention_percent=10,
        )

        self.assertEqual(str(contract), 'CT-2024-001 — ACME Holdings')
        self.assertEqual(project.contracts.count(), 1)


class PhaseAndMilestoneTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.site = Site.objects.create(code='SITE-100', name='Batangas Yard')
        cls.project = Project.objects.create(
            code='PRJ-100', name='Yard Expansion', site=cls.site,
        )

    def test_phase_sequence_must_be_unique_per_project(self):
        ProjectPhase.objects.create(
            project=self.project, name='Siteworks', sequence=1,
            status=PhaseStatus.IN_PROGRESS,
        )

        with self.assertRaises(Exception):
            ProjectPhase.objects.create(
                project=self.project, name='Duplicate', sequence=1,
            )

    def test_same_sequence_allowed_across_different_projects(self):
        other = Project.objects.create(
            code='PRJ-101', name='Other Job', site=self.site,
        )
        ProjectPhase.objects.create(project=self.project, name='A', sequence=1)
        ProjectPhase.objects.create(project=other, name='A', sequence=1)

        self.assertEqual(ProjectPhase.objects.count(), 2)

    def test_milestone_completion_and_lateness(self):
        due_past = Milestone.objects.create(
            project=self.project,
            title='Slab pour',
            due_date=timezone.localdate() - timedelta(days=3),
        )
        done = Milestone.objects.create(
            project=self.project,
            title='Permits',
            due_date=timezone.localdate() - timedelta(days=10),
            completed_date=timezone.localdate() - timedelta(days=11),
        )

        self.assertFalse(due_past.is_complete)
        self.assertTrue(due_past.is_late)

        self.assertTrue(done.is_complete)
        self.assertFalse(done.is_late)

    def test_phase_progress_cannot_exceed_100(self):
        serializer = ProjectPhaseSerializer(data={
            'project': self.project.pk,
            'name': 'Overrun',
            'sequence': 9,
            'progress_percent': '150.00',
        })

        self.assertFalse(serializer.is_valid())
        self.assertIn('progress_percent', serializer.errors)

    def test_project_serializer_rejects_target_before_start(self):
        serializer = ProjectSerializer(data={
            'code': 'PRJ-BAD',
            'name': 'Bad Dates',
            'site': self.site.pk,
            'start_date': '2024-06-01',
            'target_end_date': '2024-01-01',
        })

        self.assertFalse(serializer.is_valid())
        self.assertIn('target_end_date', serializer.errors)