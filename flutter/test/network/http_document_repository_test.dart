import 'dart:typed_data';

import 'package:buildpro_frontend/core/network/api_config.dart';
import 'package:buildpro_frontend/data/models/document.dart';
import 'package:buildpro_frontend/data/repositories/http_document_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

Map<String, dynamic> documentRow({
  int id = 1,
  int projectId = 3,
  String docType = 'plan',
  String? fileUrl,
}) => {
  'id': id,
  'project_id': projectId,
  'name': 'Structural plans S-1 to S-5',
  'doc_type': docType,
  'file_url': fileUrl ?? '$apiBaseUrl/documents/1/file/structural-s1.pdf',
  'uploaded_by': 3,
  'created_at': '2026-07-22T02:00:00Z',
  'updated_at': '2026-07-22T02:00:00Z',
};

void main() {
  group('http document repository', () {
    test('lists the documents of a project', () async {
      final api = FakeApi(
        (options) => json([documentRow(id: 1), documentRow(id: 2)]),
      );
      final repo = HttpDocumentRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final documents = await repo.getDocuments(3);

      expect(api.last('projects/3/documents/').method, 'GET');
      expect(documents.map((d) => d.id), [1, 2]);
      expect(documents.first.docType, DocumentType.plan);
      expect(documents.first.fileName, 'structural-s1.pdf');
    });

    test('uploads the real file bytes as multipart', () async {
      final api = FakeApi((options) => json(documentRow(id: 9), status: 201));
      final repo = HttpDocumentRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final saved = await repo.upload(
        projectId: 3,
        name: ' Structural plans ',
        type: DocumentType.plan,
        fileName: 'structural-s1.pdf',
        bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
        userId: 3,
      );

      final request = api.last('projects/3/documents/');
      expect(request.method, 'POST');
      expect(
        request.headers[Headers.contentTypeHeader],
        startsWith('multipart/form-data'),
      );
      final form = request.data as FormData;
      expect(
        form.fields.firstWhere((f) => f.key == 'name').value,
        'Structural plans',
      );
      expect(form.fields.firstWhere((f) => f.key == 'doc_type').value, 'plan');
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'structural-s1.pdf');
      expect(form.files.single.value.length, 4);
      expect(saved.id, 9);
    });

    test('refuses a name-only upload instead of faking success', () async {
      final api = FakeApi((options) => json(documentRow()));
      final repo = HttpDocumentRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(
        repo.upload(
          projectId: 3,
          name: 'Structural plans',
          type: DocumentType.plan,
          fileName: 'structural-s1.pdf',
          userId: 3,
        ),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            contains('Choose the file to upload'),
          ),
        ),
      );
      expect(api.requests, isEmpty);
    });

    test('deletes a document', () async {
      final api = FakeApi((options) => noContent());
      final repo = HttpDocumentRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.delete(5, userId: 3);

      expect(api.last('documents/5/').method, 'DELETE');
    });

    test('downloads the file through the authenticated client', () async {
      final api = FakeApi(
        (options) => ResponseBody.fromString(
          'pdf-bytes',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/pdf'],
          },
        ),
      );
      final repo = HttpDocumentRepository(
        testClient(
          api: api,
          tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
        ),
      );

      final bytes = await repo.download(
        Document(
          id: 1,
          projectId: 3,
          name: 'Structural plans',
          docType: DocumentType.plan,
          fileUrl: '$apiBaseUrl/documents/1/file/structural-s1.pdf',
          uploadedBy: 3,
        ),
      );

      final request = api.requests.single;
      expect(
        request.uri.toString(),
        endsWith('/documents/1/file/structural-s1.pdf'),
      );
      // The JWT rides in the header, never in the URL or a log line.
      expect(request.headers['Authorization'], 'Bearer $testAccess');
      expect(request.headers['X-Active-Role'], 'owner');
      expect(request.uri.query, isEmpty);
      expect(bytes, Uint8List.fromList('pdf-bytes'.codeUnits));
    });

    test('rethrows the server refusal text unchanged', () async {
      final api = FakeApi(
        (options) => json({
          'detail': 'Only the owner or accountant can file contracts.',
        }, status: 403),
      );
      final repo = HttpDocumentRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(
        repo.upload(
          projectId: 3,
          name: 'Contract',
          type: DocumentType.contract,
          fileName: 'contract.pdf',
          bytes: Uint8List.fromList([0x25]),
          userId: 3,
        ),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Only the owner or accountant can file contracts.',
          ),
        ),
      );
    });
  });
}
