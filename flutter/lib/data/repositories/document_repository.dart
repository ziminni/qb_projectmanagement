import '../models/document.dart';

abstract interface class DocumentRepository {
  /// Newest first.
  Future<List<Document>> getDocuments(int projectId);

  /// Owner, the project's PM or its site engineer can upload.
  Future<Document> upload({
    required int projectId,
    required String name,
    required DocumentType type,
    required String fileName,
    required int userId,
  });

  /// The uploader, the project's PM or the owner can delete.
  Future<void> delete(int id, {required int userId});
}
