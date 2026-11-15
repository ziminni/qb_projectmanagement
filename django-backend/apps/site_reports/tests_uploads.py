"""Phase 2.2 upload security: documents, report photos and private serving.

Proves contract security checks 1, 3, 5 and 6 for the 2.2 surface: extension and
magic-byte agreement, the size caps, path-traversal names, random stored names,
scoped/authenticated download only, contract documents finance-only, and the
`MEDIA_URL` hole staying closed. Texts marked *proposed* in the contract are the
ones this file asserts.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

import os
import shutil
import tempfile
from datetime import UTC, date, datetime
from unittest import mock
from urllib.parse import urlsplit

from django.core.files.base import ContentFile
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings

from ..users.models import Role
from .models import Document, ReportPhoto
from .tests_api import SiteReportCase

PDF_BYTES = b'%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n%%EOF\n'
PNG_BYTES = b'\x89PNG\r\n\x1a\n' + b'\x00' * 40
JPG_BYTES = b'\xff\xd8\xff\xe0\x00\x10JFIF\x00' + b'\x00' * 32
DOCX_BYTES = b'PK\x03\x04\x14\x00\x06\x00' + b'\x00' * 32
DWG_BYTES = b'AC1015' + b'\x00' * 32
DXF_BYTES = b'0\nSECTION\n2\nHEADER\n0\nENDSEC\n0\nEOF\n'
HTML_BYTES = b'<html><script>alert(1)</script></html>'

BAD_TYPE = (
    'Choose a file of type pdf, dwg, dxf, jpg, jpeg, png, doc, docx, xls, xlsx.'
)
NOT_AN_UPLOADER = "Only the project's owner or site engineer can upload."
NOT_A_CONTRACT_FILER = 'Only the owner or accountant can file contracts.'
DUPLICATE_NAME = 'A document with this name already exists in this section.'
NOT_A_DELETER = 'Only the uploader or the owner can delete this document.'
NAME_NOT_ALLOWED = 'The file name is not allowed.'


class UploadCase(SiteReportCase):
    """The daily-report fixtures plus a throwaway private `MEDIA_ROOT`."""

    def setUp(self):
        super().setUp()
        self.media_root = tempfile.mkdtemp(prefix='cpms-private-media-')
        override = override_settings(MEDIA_ROOT=self.media_root)
        override.enable()
        self.addCleanup(override.disable)
        self.addCleanup(shutil.rmtree, self.media_root, True)

    def upload_document(self, *, user=None, role=None, name='Building permit',
                        doc_type='permit', file_name='permit-a1.pdf',
                        content=PDF_BYTES, project=None):
        from django.core.files.uploadedfile import SimpleUploadedFile

        self.act_as(user or self.owner, role or Role.OWNER)
        return self.client.post(
            f'/api/v1/projects/{(project or self.project).pk}/documents/',
            {
                'name': name,
                'doc_type': doc_type,
                'file': SimpleUploadedFile(file_name, content),
            },
            format='multipart',
        )

    def upload_photo(self, report, *, user=None, file_name='slab.png',
                     content=PNG_BYTES, caption='Slab pour'):
        from django.core.files.uploadedfile import SimpleUploadedFile

        user = user or self.engineer
        self.act_as(user, Role.SITE_ENGINEER)
        return self.client.post(
            f'/api/v1/daily-reports/{report.pk}/photos/',
            {
                'file': SimpleUploadedFile(file_name, content),
                'caption': caption,
                'latitude': '10.315700',
                'longitude': '123.885400',
                'taken_at': '2026-11-15T08:30:00Z',
            },
            format='multipart',
        )

    def make_document(self, project, name='Hidden plan', doc_type='plan'):
        from django.core.files.base import ContentFile

        document = Document(project=project, name=name, doc_type=doc_type,
                            file_name='hidden.pdf', uploaded_by=self.owner)
        document.file.save('hidden.pdf', ContentFile(PDF_BYTES), save=False)
        document.save()
        return document

    def fetch(self, url, user=None, role=None):
        self.act_as(user or self.owner, role or Role.OWNER)
        return self.client.get(urlsplit(url).path)


class DocumentUploadTests(UploadCase):
    def test_owner_uploads_and_the_file_downloads_as_an_attachment(self):
        response = self.upload_document()

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(
            set(response.data), {
                'id', 'project_id', 'name', 'doc_type', 'file_url',
                'uploaded_by', 'created_at', 'updated_at',
            },
        )
        self.assertEqual(response.data['doc_type'], 'permit')
        self.assertEqual(response.data['uploaded_by'], self.owner.pk)
        # Flutter reads the displayed name from the last path segment.
        self.assertTrue(response.data['file_url'].endswith('/permit-a1.pdf'))

        download = self.fetch(response.data['file_url'])
        self.assertEqual(download.status_code, 200)
        self.assertEqual(b''.join(download.streaming_content), PDF_BYTES)
        self.assertIn('attachment;', download['Content-Disposition'])
        self.assertEqual(download['X-Content-Type-Options'], 'nosniff')
        self.assertEqual(download['Cache-Control'], 'private, no-store')

        stored = Document.objects.get(pk=response.data['id'])
        self.assertNotIn('permit-a1', stored.file.name)

    def test_a_site_engineer_may_upload(self):
        response = self.upload_document(user=self.engineer, role=Role.SITE_ENGINEER)

        self.assertEqual(response.status_code, 201, response.data)

    def test_only_the_owner_or_site_engineer_may_upload(self):
        for user, role in (
            (self.admin, Role.ADMIN),
            (self.accountant, Role.ACCOUNTANT),
            (self.client_user, Role.CLIENT),
        ):
            with self.subTest(role=role):
                response = self.upload_document(user=user, role=role)

                self.assertEqual(response.status_code, 403, response.data)
                self.assertEqual(response.data['detail'], NOT_AN_UPLOADER)
        self.assertFalse(Document.objects.exists())

    def test_an_out_of_scope_project_is_404(self):
        response = self.upload_document(project=self.other_project)

        self.assertEqual(response.status_code, 404, response.data)
        self.assertFalse(Document.objects.exists())

    def test_a_file_type_outside_the_list_is_refused(self):
        response = self.upload_document(file_name='payload.exe', content=b'MZ\x90')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], BAD_TYPE)

    def test_extension_and_content_must_agree(self):
        for file_name, content in (
            ('plans.pdf', HTML_BYTES),
            ('plans.dwg', PDF_BYTES),
            ('photo.png', JPG_BYTES),
            ('sheet.dxf', PDF_BYTES),
        ):
            with self.subTest(file_name=file_name):
                response = self.upload_document(
                    file_name=file_name, content=content,
                )

                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(
                    response.data['detail'],
                    f'The file does not look like a {file_name.rsplit(".", 1)[1]} file.',
                )
        self.assertFalse(Document.objects.exists())

    def test_every_allowed_type_is_accepted_with_matching_content(self):
        for index, (file_name, content) in enumerate((
            ('plans.pdf', PDF_BYTES),
            ('photo.jpg', JPG_BYTES),
            ('photo.jpeg', JPG_BYTES),
            ('scan.png', PNG_BYTES),
            ('report.docx', DOCX_BYTES),
            ('sheet.dwg', DWG_BYTES),
            ('sheet.dxf', DXF_BYTES),
        )):
            with self.subTest(file_name=file_name):
                response = self.upload_document(
                    name=f'File {index}', file_name=file_name, content=content,
                )

                self.assertEqual(response.status_code, 201, response.data)

    def test_an_oversize_document_is_refused(self):
        big = b'%PDF-1.4\n' + b'0' * (25 * 1024 * 1024)

        response = self.upload_document(content=big)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], 'The file is larger than 25 MB.')
        self.assertFalse(Document.objects.exists())

    def test_a_path_traversal_file_name_never_escapes_the_private_media_root(self):
        """Multipart parsing strips the path; whatever survives must stay inside."""
        for file_name in ('../../x.pdf', 'sub/dir/x.pdf', '..\\x.pdf'):
            with self.subTest(file_name=file_name):
                response = self.upload_document(
                    name=f'Safe {file_name}', file_name=file_name,
                )

                if response.status_code == 400:
                    # Our own guard refused a name that still carried a separator.
                    self.assertEqual(response.data['detail'], NAME_NOT_ALLOWED)
                    continue
                self.assertEqual(response.status_code, 201, response.data)
                stored = Document.objects.get(pk=response.data['id'])
                self.assertEqual(stored.file_name, 'x.pdf')
                self.assertNotIn('/', stored.file_name)
                self.assertTrue(stored.file.path.startswith(self.media_root))
                self.assertTrue(response.data['file_url'].endswith('/x.pdf'))

    def test_the_name_validator_refuses_what_survives_multipart_parsing(self):
        """Django basenames `/` paths; a backslash path and a dot name reach us."""
        from django.core.files.uploadedfile import SimpleUploadedFile

        from . import uploads

        for raw, expected in (('../../x.pdf', 'x.pdf'), ('sub/dir/x.pdf', 'x.pdf')):
            with self.subTest(name=raw):
                # Django's own file-name setter strips the directory part.
                self.assertEqual(
                    uploads.display_name(SimpleUploadedFile(raw, PDF_BYTES)), expected,
                )

        for raw in ('..\\x.pdf', '.hidden.pdf'):
            with self.subTest(name=raw):
                with self.assertRaises(Exception) as caught:
                    uploads.display_name(SimpleUploadedFile(raw, PDF_BYTES))

                self.assertEqual(str(caught.exception.detail), NAME_NOT_ALLOWED)

    def test_a_duplicate_name_in_the_same_section_is_refused(self):
        self.assertEqual(self.upload_document().status_code, 201)

        response = self.upload_document(name='building permit')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], DUPLICATE_NAME)

    def test_the_same_name_in_another_section_is_allowed(self):
        self.assertEqual(self.upload_document().status_code, 201)

        response = self.upload_document(doc_type='plan')

        self.assertEqual(response.status_code, 201, response.data)

    def test_the_name_must_be_given(self):
        response = self.upload_document(name='   ')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], 'Enter the document name.')


class DocumentReadScopeTests(UploadCase):
    def test_contracts_are_hidden_from_admin_and_site_engineer(self):
        contract = self.upload_document(
            name='Contract', doc_type='contract', file_name='contract.pdf',
        )
        plan = self.upload_document(
            name='Plans', doc_type='plan', file_name='plans.pdf',
        )
        self.assertEqual(contract.status_code, 201, contract.data)

        for user, role in ((self.admin, Role.ADMIN), (self.engineer, Role.SITE_ENGINEER)):
            with self.subTest(role=role):
                self.act_as(user, role)
                listing = self.client.get(
                    f'/api/v1/projects/{self.project.pk}/documents/',
                )

                self.assertEqual(listing.status_code, 200, listing.data)
                self.assertEqual(
                    [row['id'] for row in listing.data], [plan.data['id']],
                )
                self.assertEqual(
                    self.fetch(contract.data['file_url'], user, role).status_code,
                    404,
                )

    def test_finance_roles_see_the_contract(self):
        contract = self.upload_document(
            name='Contract', doc_type='contract', file_name='contract.pdf',
        )

        for user, role in ((self.owner, Role.OWNER), (self.accountant, Role.ACCOUNTANT)):
            with self.subTest(role=role):
                self.act_as(user, role)
                listing = self.client.get(
                    f'/api/v1/projects/{self.project.pk}/documents/',
                )

                self.assertEqual(
                    [row['id'] for row in listing.data], [contract.data['id']],
                )

    def test_a_site_engineer_cannot_file_a_contract(self):
        response = self.upload_document(
            user=self.engineer, role=Role.SITE_ENGINEER,
            doc_type='contract', file_name='contract.pdf',
        )

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(response.data['detail'], NOT_A_CONTRACT_FILER)

    def test_client_cannot_list_or_download_documents(self):
        document = self.upload_document()
        self.act_as(self.client_user, Role.CLIENT)

        listing = self.client.get(f'/api/v1/projects/{self.project.pk}/documents/')
        download = self.client.get(urlsplit(document.data['file_url']).path)

        self.assertEqual(listing.status_code, 403, listing.data)
        self.assertIn(download.status_code, (403, 404))

    def test_documents_are_out_of_scope_per_project(self):
        hidden = self.make_document(self.other_project)
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        listing = self.client.get(
            f'/api/v1/projects/{self.other_project.pk}/documents/',
        )
        download = self.client.get(
            f'/api/v1/documents/{hidden.pk}/file/{hidden.file_name}',
        )

        self.assertEqual(listing.status_code, 404, listing.data)
        self.assertEqual(download.status_code, 404)

    def test_a_wrong_file_name_in_the_url_is_404(self):
        document = self.upload_document()
        self.act_as(self.owner, Role.OWNER)

        response = self.client.get(
            f'/api/v1/documents/{document.data["id"]}/file/other.pdf',
        )

        self.assertEqual(response.status_code, 404)

    def test_the_file_needs_authentication(self):
        document = self.upload_document()
        self.client.force_authenticate(user=None)
        self.client.credentials()

        response = self.client.get(urlsplit(document.data['file_url']).path)

        self.assertIn(response.status_code, (401, 403))

    def test_media_url_serves_nothing(self):
        document = self.upload_document()
        stored = Document.objects.get(pk=document.data['id'])

        response = self.client.get(f'/api/v1/private-media/{stored.file.name}')

        self.assertEqual(response.status_code, 404)


class DocumentDeleteTests(UploadCase):
    def test_the_uploader_deletes_their_document_and_the_file_goes(self):
        document = self.upload_document(
            user=self.engineer, role=Role.SITE_ENGINEER,
        )
        stored = Document.objects.get(pk=document.data['id'])
        path = stored.file.path
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        # The file goes on commit, not before the row (review 2.2).
        with self.captureOnCommitCallbacks(execute=True):
            response = self.client.delete(f'/api/v1/documents/{document.data["id"]}/')

        self.assertEqual(response.status_code, 204, response.data)
        self.assertFalse(Document.objects.exists())
        self.assertFalse(os.path.exists(path))

    def test_the_project_owner_may_delete_someone_elses_document(self):
        document = self.upload_document(
            user=self.engineer, role=Role.SITE_ENGINEER,
        )
        self.act_as(self.owner, Role.OWNER)

        response = self.client.delete(f'/api/v1/documents/{document.data["id"]}/')

        self.assertEqual(response.status_code, 204, response.data)

    def test_another_site_engineer_may_not_delete(self):
        document = self.upload_document(
            user=self.engineer, role=Role.SITE_ENGINEER,
        )
        self.act_as(self.engineer2, Role.SITE_ENGINEER)

        response = self.client.delete(f'/api/v1/documents/{document.data["id"]}/')

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(response.data['detail'], NOT_A_DELETER)
        self.assertTrue(Document.objects.exists())

    def test_deleting_another_projects_document_is_404(self):
        hidden = self.make_document(self.other_project)
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.delete(f'/api/v1/documents/{hidden.pk}/')

        self.assertEqual(response.status_code, 404, response.data)
        self.assertTrue(Document.objects.filter(pk=hidden.pk).exists())


class ReportPhotoTests(UploadCase):
    def test_the_author_uploads_a_photo_to_their_draft(self):
        report = self.make_report()

        response = self.upload_photo(report)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(
            set(response.data), {
                'id', 'daily_report_id', 'file_url', 'caption', 'latitude',
                'longitude', 'taken_at', 'created_at', 'updated_at',
            },
        )
        self.assertTrue(response.data['file_url'].endswith('/slab.png'))
        self.assertEqual(response.data['caption'], 'Slab pour')
        self.assertEqual(
            datetime.fromisoformat(response.data['taken_at']),
            datetime(2026, 11, 15, 8, 30, tzinfo=UTC),
        )

        download = self.fetch(response.data['file_url'])
        self.assertEqual(download.status_code, 200)
        self.assertEqual(b''.join(download.streaming_content), PNG_BYTES)
        self.assertIn('inline;', download['Content-Disposition'])
        self.assertEqual(download['X-Content-Type-Options'], 'nosniff')

    def test_photo_types_and_contents_are_checked(self):
        report = self.make_report()
        cases = (
            ('shot.gif', PNG_BYTES, 'Choose a file of type jpg, jpeg, png, webp.'),
            ('shot.png', JPG_BYTES, 'The file does not look like a png file.'),
            ('shot.jpg', HTML_BYTES, 'The file does not look like a jpg file.'),
        )
        for file_name, content, expected in cases:
            with self.subTest(file_name=file_name):
                response = self.upload_photo(report, file_name=file_name, content=content)

                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(response.data['detail'], expected)

    def test_an_oversize_photo_is_refused(self):
        report = self.make_report()

        response = self.upload_photo(
            report, content=PNG_BYTES + b'0' * (10 * 1024 * 1024),
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], 'The file is larger than 10 MB.')

    def test_only_the_author_edits_photos_and_only_while_editable(self):
        report = self.make_report()
        not_author = self.upload_photo(report, user=self.engineer2)
        self.assertEqual(not_author.status_code, 403, not_author.data)
        self.assertEqual(
            not_author.data['detail'],
            'Only the site engineer who wrote this report can change its photos.',
        )

        approved = self.make_report(report_date=date(2026, 11, 10), status='approved')
        locked = self.upload_photo(approved)
        self.assertEqual(locked.status_code, 400, locked.data)
        self.assertEqual(
            locked.data['detail'],
            'This report is approved and can no longer be edited.',
        )

    def test_uploading_to_an_out_of_scope_report_is_404(self):
        report = self.make_report(project=self.other_project, author=self.engineer)

        response = self.upload_photo(report)

        self.assertEqual(response.status_code, 404, response.data)

    def test_a_draft_photo_file_is_staff_only_but_approved_is_shared(self):
        draft = self.make_report()
        draft_photo = ReportPhoto(daily_report=draft)
        draft_photo.file.save('draft.png', ContentFile(PNG_BYTES), save=True)
        draft_photo.file_name = 'draft.png'
        draft_photo.save(update_fields=['file_name'])

        approved = self.make_report(report_date=date(2026, 11, 10), status='approved')
        approved_photo = ReportPhoto(daily_report=approved)
        approved_photo.file.save('ok.png', ContentFile(PNG_BYTES), save=True)
        approved_photo.file_name = 'ok.png'
        approved_photo.save(update_fields=['file_name'])

        self.act_as(self.client_user, Role.CLIENT)
        shared = self.client.get(
            f'/api/v1/report-photos/{approved_photo.pk}/file/ok.png',
        )
        hidden = self.client.get(
            f'/api/v1/report-photos/{draft_photo.pk}/file/draft.png',
        )

        self.assertEqual(shared.status_code, 200)
        self.assertEqual(hidden.status_code, 404)


class DocumentAuditTests(UploadCase):
    def test_upload_and_delete_are_audited(self):
        from ..users.models import AuditLog

        document = self.upload_document()
        self.act_as(self.owner, Role.OWNER)
        self.client.delete(f'/api/v1/documents/{document.data["id"]}/')

        uploaded = AuditLog.objects.get(
            action='document_uploaded', entity='document',
            entity_id=document.data['id'],
        )
        self.assertEqual(uploaded.details['doc_type'], 'permit')
        self.assertTrue(
            AuditLog.objects.filter(
                action='document_deleted', entity_id=document.data['id'],
            ).exists()
        )


class ReportPhotoDraftTests(UploadCase):
    def test_a_photo_removed_through_the_draft_is_deleted_with_its_file(self):
        report = self.make_report()
        created = self.upload_photo(report)
        stored = ReportPhoto.objects.get(pk=created.data['id'])
        path = stored.file.path
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        # The file goes on commit, not inside the transaction (review 2.2).
        with self.captureOnCommitCallbacks(execute=True):
            response = self.client.put(
                f'/api/v1/daily-reports/{report.pk}/',
                {
                    'report_date': report.report_date.isoformat(),
                    'weather': 'sunny',
                    'photos': [],
                },
                format='json',
            )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(ReportPhoto.objects.exists())
        self.assertFalse(os.path.exists(path))

    def test_a_photo_of_another_projects_report_is_404(self):
        other_report = self.make_report(
            project=self.other_project, author=self.engineer,
        )
        hidden = ReportPhoto(daily_report=other_report, file_name='hidden.png')
        hidden.file.save('hidden.png', ContentFile(PNG_BYTES), save=False)
        hidden.save()
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.get(
            f'/api/v1/report-photos/{hidden.pk}/file/hidden.png',
        )

        self.assertEqual(response.status_code, 404)


class TodoForeignKeyTests(UploadCase):
    """The 2.1 integer becomes a real nullable FK without losing a value."""

    def test_the_link_is_a_foreign_key_that_survives_report_deletion(self):
        report = self.make_report()
        self.todo.daily_report_id = report.pk
        self.todo.save(update_fields=['daily_report_id'])

        self.todo.refresh_from_db()
        self.assertEqual(self.todo.daily_report, report)

        report.delete()

        self.todo.refresh_from_db()
        self.assertIsNone(self.todo.daily_report_id)


# A minimal RIFF/WEBP header: `RIFF` + little-endian size + `WEBP` + chunk.
WEBP_BYTES = b'RIFF\x24\x00\x00\x00WEBPVP8 ' + b'\x00' * 32
# A RIFF container that is **not** WebP (e.g. a WAV file) and a truncated one.
RIFF_WAVE_BYTES = b'RIFF\x24\x00\x00\x00WAVEfmt ' + b'\x00' * 32
TRUNCATED_WEBP_BYTES = b'RIFF\x24\x00\x00\x00WEB'


class WebPPhotoTests(UploadCase):
    """Decision 06 #7 asks for WebP report photos, checked like the rest."""

    def test_a_webp_photo_is_accepted_and_served_as_webp(self):
        report = self.make_report()

        response = self.upload_photo(
            report, file_name='slab.webp', content=WEBP_BYTES,
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(response.data['file_url'].endswith('/slab.webp'))
        download = self.fetch(response.data['file_url'])
        self.assertEqual(download.status_code, 200)
        self.assertEqual(download['Content-Type'], 'image/webp')
        self.assertEqual(b''.join(download.streaming_content), WEBP_BYTES)

    def test_a_non_webp_riff_and_a_truncated_webp_are_refused(self):
        report = self.make_report()
        cases = (
            ('shot.webp', RIFF_WAVE_BYTES),
            ('shot.webp', TRUNCATED_WEBP_BYTES),
            ('shot.webp', b'RIFF' + b'\x00' * 40),
            ('shot.webp', PNG_BYTES),
        )
        for file_name, content in cases:
            with self.subTest(content=content[:12]):
                response = self.upload_photo(
                    report, file_name=file_name, content=content,
                )

                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(
                    response.data['detail'],
                    'The file does not look like a webp file.',
                )
        self.assertFalse(ReportPhoto.objects.exists())

    def test_the_photo_type_list_in_the_refusal_mentions_webp(self):
        report = self.make_report()

        response = self.upload_photo(report, file_name='shot.gif', content=PNG_BYTES)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'], 'Choose a file of type jpg, jpeg, png, webp.',
        )


class UploadTransactionTests(UploadCase):
    """Review 2.2 warning: a file must never outlive (or precede) its row.

    File removal is deferred with `transaction.on_commit`, so a rolled-back
    save/delete leaves the row and its file together; a save that fails after
    the file was written leaves no orphan behind.
    """

    def media_files(self):
        found = []
        for root, _dirs, names in os.walk(self.media_root):
            for name in names:
                found.append(os.path.join(root, name))
        return found

    def test_a_rolled_back_photo_removal_keeps_the_row_and_its_file(self):
        from . import services

        report = self.make_report()
        created = self.upload_photo(report)
        stored = ReportPhoto.objects.get(pk=created.data['id'])
        path = stored.file.path
        payload = {
            'report_date': report.report_date.isoformat(),
            'weather': 'sunny',
            'photos': [],
        }

        with (
            mock.patch.object(
                services, '_apply_todos', side_effect=RuntimeError('save failed'),
            ),
            self.assertRaises(RuntimeError),
        ):
            services.save_draft(
                self.engineer, Role.SITE_ENGINEER, payload, report=report,
            )

        self.assertTrue(ReportPhoto.objects.filter(pk=stored.pk).exists())
        self.assertEqual(stored.file_name, 'slab.png')
        self.assertTrue(os.path.exists(path))

    def test_a_rolled_back_delete_keeps_the_document_row_and_its_file(self):
        from . import services

        document = self.upload_document()
        stored = Document.objects.get(pk=document.data['id'])
        stored_id = stored.pk
        path = stored.file.path

        with (
            mock.patch.object(
                services, 'record', side_effect=RuntimeError('audit failed'),
            ),
            self.assertRaises(RuntimeError),
        ):
            services.delete_document(self.owner, stored)

        self.assertTrue(Document.objects.filter(pk=stored_id).exists())
        self.assertTrue(os.path.exists(path))

    def test_a_failed_document_save_leaves_no_orphan_file(self):
        from . import services

        before = self.media_files()

        with (
            mock.patch.object(
                services, 'record', side_effect=RuntimeError('audit failed'),
            ),
            self.assertRaises(RuntimeError),
        ):
            services.upload_document(
                self.owner, Role.OWNER, self.project,
                SimpleUploadedFile('orphan.pdf', PDF_BYTES),
                {'name': 'Orphan', 'doc_type': 'permit'},
            )

        self.assertFalse(Document.objects.exists())
        self.assertEqual(self.media_files(), before)

    def test_a_failed_photo_save_leaves_no_orphan_file(self):
        from . import services

        report = self.make_report()
        before = self.media_files()

        with (
            mock.patch.object(
                ReportPhoto, 'save', side_effect=RuntimeError('save failed'),
            ),
            self.assertRaises(RuntimeError),
        ):
            services.upload_photo(
                self.engineer, report,
                SimpleUploadedFile('slab.png', PNG_BYTES), {},
            )

        self.assertFalse(ReportPhoto.objects.exists())
        self.assertEqual(self.media_files(), before)

    def test_a_committed_removal_still_deletes_the_file(self):
        report = self.make_report()
        created = self.upload_photo(report)
        stored = ReportPhoto.objects.get(pk=created.data['id'])
        path = stored.file.path
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        with self.captureOnCommitCallbacks(execute=True):
            response = self.client.put(
                f'/api/v1/daily-reports/{report.pk}/',
                {
                    'report_date': report.report_date.isoformat(),
                    'weather': 'sunny',
                    'photos': [],
                },
                format='json',
            )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(ReportPhoto.objects.exists())
        self.assertFalse(os.path.exists(path))
