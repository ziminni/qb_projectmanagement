import 'dart:typed_data';

import '../models/document.dart';

abstract interface class DocumentRepository {
  /// Newest first.
  Future<List<Document>> getDocuments(int projectId);

  /// Owner, the project's PM or its site engineer can upload.
  ///
  /// [bytes] is the file content: the server stores the file and checks its
  /// type by magic bytes, so a name alone is not an upload. It stays optional
  /// for the demo data, which stores a placeholder; the HTTP repository
  /// refuses to upload without it.
  Future<Document> upload({
    required int projectId,
    required String name,
    required DocumentType type,
    required String fileName,
    Uint8List? bytes,
    required int userId,
  });

  /// The file content, fetched with the JWT (files are private).
  Future<Uint8List> download(Document document);

  /// The uploader, the project's PM or the owner can delete.
  Future<void> delete(int id, {required int userId});
}
