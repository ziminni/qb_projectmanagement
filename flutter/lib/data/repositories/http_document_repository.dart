import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../models/document.dart';
import '../services/business_rule_exception.dart';
import 'document_repository.dart';

/// Project documents, against the CPMS backend.
///
/// Files are private: the upload is multipart (the server checks the type by
/// magic bytes and caps the size), and the download goes through the JWT
/// client — never a public URL, never a token in a query string. `file_url`
/// always ends in the stored file name, which the screen shows.
class HttpDocumentRepository implements DocumentRepository {
  HttpDocumentRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Document>> getDocuments(int projectId) async => [
    for (final row in await _client.getRows('projects/$projectId/documents/'))
      Document.fromJson(row),
  ];

  @override
  Future<Document> upload({
    required int projectId,
    required String name,
    required DocumentType type,
    required String fileName,
    Uint8List? bytes,
    required int userId,
  }) async {
    if (bytes == null || bytes.isEmpty) {
      // A file name is not a file: refuse instead of saving an empty record.
      throw const BusinessRuleException('Choose the file to upload.');
    }
    final form = FormData.fromMap({
      'name': name.trim(),
      'doc_type': type.apiValue,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName.trim().split(RegExp(r'[\\/]')).last,
      ),
    });
    return Document.fromJson(
      jsonObject(
        await _client.post('projects/$projectId/documents/', body: form),
      ),
    );
  }

  @override
  Future<Uint8List> download(Document document) =>
      _client.getBytes(document.fileUrl);

  @override
  Future<void> delete(int id, {required int userId}) =>
      _client.delete('documents/$id/');
}
