import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/document.dart';
import 'package:buildpro_frontend/data/repositories/mock_document_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  late MockDocumentRepository repo;
  setUp(() => repo = MockDocumentRepository(projects: getIt()));

  Matcher throwsRule(String fragment) => throwsA(
    isA<BusinessRuleException>().having(
      (e) => e.message,
      'message',
      contains(fragment),
    ),
  );

  test('upload rules: who, file type and duplicate names', () async {
    // Liza (accountant) is not on the site team.
    expect(
      repo.upload(
        projectId: 1,
        name: 'X',
        type: DocumentType.plan,
        fileName: 'x.pdf',
        userId: 6,
      ),
      throwsRule('Only the project'),
    );
    expect(
      repo.upload(
        projectId: 1,
        name: 'X',
        type: DocumentType.plan,
        fileName: 'x.exe',
        userId: 3,
      ),
      throwsRule('Choose a file of type'),
    );
    expect(
      repo.upload(
        projectId: 1,
        name: 'building permit',
        type: DocumentType.permit,
        fileName: 'p.pdf',
        userId: 3,
      ),
      throwsRule('already exists'),
    );
    final doc = await repo.upload(
      projectId: 1,
      name: 'As-built electrical',
      type: DocumentType.asBuilt,
      fileName: 'asbuilt-e.pdf',
      userId: 4,
    );
    expect(doc.fileName, 'asbuilt-e.pdf');
  });

  test('only the uploader or the owner can delete', () async {
    // Doc 4 was uploaded by the owner; Ana is the site engineer.
    expect(repo.delete(4, userId: 4), throwsRule('Only the uploader'));
    await repo.delete(4, userId: 3);
    expect((await repo.getDocuments(1)).any((d) => d.id == 4), isFalse);
  });

  testWidgets('documents tab groups by type and uploads', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/projects/1/documents');
    expect(find.text('Plans (2)'), findsOneWidget);
    expect(find.text('Permits (1)'), findsOneWidget);
    await tester.tap(find.text('Upload document'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Document name'),
      'Electrical plans',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'File'),
      'electrical.pdf',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
    await tester.pumpAndSettle();
    expect(find.text('Plans (3)'), findsOneWidget);
  });
}
