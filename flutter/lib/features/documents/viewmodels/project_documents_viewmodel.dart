import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/document.dart';
import '../../../data/repositories/document_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/session_service.dart';

/// Project "Documents" tab: contracts, plans, permits, as-built drawings.
class ProjectDocumentsViewModel extends ChangeNotifier with ActionRunner {
  ProjectDocumentsViewModel({
    required this.projectId,
    required SessionService session,
    required DocumentRepository documents,
    required UserRepository users,
  }) : _session = session,
       _documents = documents,
       _users = users;

  final int projectId;
  final SessionService _session;
  final DocumentRepository _documents;
  final UserRepository _users;

  bool _loading = true;
  List<Document> _items = const [];
  Map<int, String> _userNames = const {};

  bool get isLoading => _loading;
  String userName(int id) => _userNames[id] ?? 'User #$id';

  /// Documents grouped by type, in the type's order.
  Map<DocumentType, List<Document>> get grouped => {
    for (final t in DocumentType.values)
      if (_items.any((d) => d.docType == t))
        t: _items.where((d) => d.docType == t).toList(),
  };

  bool get canUpload =>
      const [AppRole.owner, AppRole.siteEngineer].contains(_session.activeRole);

  bool canDelete(Document d) =>
      d.uploadedBy == _session.user!.id || _session.activeRole == AppRole.owner;

  /// Contracts carry the contract price, so only finance roles see them.
  List<DocumentType> get uploadTypes => [
    for (final t in DocumentType.values)
      if (t != DocumentType.contract || _session.activeRole!.seesFinance) t,
  ];

  Future<List<Document>> _visible() async => [
    for (final d in await _documents.getDocuments(projectId))
      if (uploadTypes.contains(d.docType)) d,
  ];

  Future<void> load() async {
    _items = await _visible();
    _userNames = {for (final u in await _users.getUsers()) u.id: u.fullName};
    _loading = false;
    notifyListeners();
  }

  Future<String?> upload({
    required String name,
    required DocumentType type,
    required String fileName,
  }) => runAction(() async {
    await _documents.upload(
      projectId: projectId,
      name: name,
      type: type,
      fileName: fileName,
      userId: _session.user!.id,
    );
    _items = await _visible();
  });

  Future<String?> delete(Document d) => runAction(() async {
    await _documents.delete(d.id, userId: _session.user!.id);
    _items = await _visible();
  });
}
