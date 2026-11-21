import 'dart:typed_data';

import '../../data/services/business_rule_exception.dart';
import 'api_client.dart';

/// Loads private server files (documents, site photos) through the
/// JWT-carrying [ApiClient]. `Image.network` cannot work for these files: the
/// server answers only a scoped, authenticated request and never publishes a
/// token in a URL. Null client = mock mode, where files are placeholders.
class PrivateFileLoader {
  PrivateFileLoader(this._client);

  final ApiClient? _client;

  Future<Uint8List> bytes(String fileUrl) {
    final client = _client;
    if (client == null) {
      throw const BusinessRuleException(
        'Files are stored on the server; the demo has none.',
      );
    }
    final normalized = fileUrl.startsWith('/api/v1/')
        ? fileUrl.substring('/api/v1/'.length)
        : fileUrl;
    return client.getBytes(normalized);
  }
}
