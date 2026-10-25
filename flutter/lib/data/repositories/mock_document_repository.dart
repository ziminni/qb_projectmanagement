import '../models/app_role.dart';
import '../models/document.dart';
import '../services/business_rule_exception.dart';
import 'document_repository.dart';
import 'project_repository.dart';
import 'user_repository.dart';

class MockDocumentRepository implements DocumentRepository {
  MockDocumentRepository({
    required ProjectRepository projects,
    required UserRepository users,
  }) : _projects = projects,
       _users = users;

  final ProjectRepository _projects;
  final UserRepository _users;

  static final _allowedExtensions = {
    'pdf',
    'dwg',
    'dxf',
    'jpg',
    'jpeg',
    'png',
    'doc',
    'docx',
    'xls',
    'xlsx',
  };

  final _docs = <Document>[
    Document(
      id: 1,
      projectId: 1,
      name: 'Construction contract',
      docType: DocumentType.contract,
      fileUrl: 'mock://documents/qb-2026-014-contract.pdf',
      uploadedBy: 2,
      createdAt: DateTime(2026, 7, 20),
    ),
    Document(
      id: 2,
      projectId: 1,
      name: 'Architectural plans A-1 to A-8',
      docType: DocumentType.plan,
      fileUrl: 'mock://documents/architectural-a1-a8.pdf',
      uploadedBy: 3,
      createdAt: DateTime(2026, 7, 22),
    ),
    Document(
      id: 3,
      projectId: 1,
      name: 'Structural plans S-1 to S-5',
      docType: DocumentType.plan,
      fileUrl: 'mock://documents/structural-s1-s5.dwg',
      uploadedBy: 3,
      createdAt: DateTime(2026, 7, 22),
    ),
    Document(
      id: 4,
      projectId: 1,
      name: 'Building permit',
      docType: DocumentType.permit,
      fileUrl: 'mock://documents/building-permit-lipa.pdf',
      uploadedBy: 3,
      createdAt: DateTime(2026, 7, 29),
    ),
    Document(
      id: 5,
      projectId: 2,
      name: 'Construction contract',
      docType: DocumentType.contract,
      fileUrl: 'mock://documents/qb-2026-018-contract.pdf',
      uploadedBy: 2,
      createdAt: DateTime(2026, 9, 1),
    ),
  ];

  @override
  Future<List<Document>> getDocuments(int projectId) async =>
      _docs.where((d) => d.projectId == projectId).toList()..sort(
        (a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
      );

  Future<bool> _canUpload(int projectId, int userId) async {
    if ((await _users.getRoles(userId)).contains(AppRole.owner)) return true;
    return await _projects.isAssigned(projectId, userId, AppRole.pm) ||
        await _projects.isAssigned(projectId, userId, AppRole.siteEngineer);
  }

  @override
  Future<Document> upload({
    required int projectId,
    required String name,
    required DocumentType type,
    required String fileName,
    required int userId,
  }) async {
    if (!await _canUpload(projectId, userId)) {
      throw const BusinessRuleException(
        'Only the owner and the project\'s PM or site engineer can upload.',
      );
    }
    if (name.trim().isEmpty) {
      throw const BusinessRuleException('Enter the document name.');
    }
    final file = fileName.trim();
    final ext = file.contains('.') ? file.split('.').last.toLowerCase() : '';
    if (!_allowedExtensions.contains(ext)) {
      throw BusinessRuleException(
        'Choose a file of type ${_allowedExtensions.join(', ')}.',
      );
    }
    if (_docs.any(
      (d) =>
          d.projectId == projectId &&
          d.docType == type &&
          d.name.toLowerCase() == name.trim().toLowerCase(),
    )) {
      throw const BusinessRuleException(
        'A document with this name already exists in this section.',
      );
    }
    final doc = Document(
      id: _docs.fold(0, (m, d) => d.id > m ? d.id : m) + 1,
      projectId: projectId,
      name: name.trim(),
      docType: type,
      fileUrl: 'mock://documents/$file',
      uploadedBy: userId,
      createdAt: DateTime.now(),
    );
    _docs.add(doc);
    return doc;
  }

  @override
  Future<void> delete(int id, {required int userId}) async {
    final i = _docs.indexWhere((d) => d.id == id);
    if (i < 0) throw const BusinessRuleException('Document not found.');
    final d = _docs[i];
    final allowed =
        d.uploadedBy == userId ||
        (await _users.getRoles(userId)).contains(AppRole.owner) ||
        await _projects.isAssigned(d.projectId, userId, AppRole.pm);
    if (!allowed) {
      throw const BusinessRuleException(
        'Only the uploader, the PM or the owner can delete this document.',
      );
    }
    _docs.removeAt(i);
  }
}
