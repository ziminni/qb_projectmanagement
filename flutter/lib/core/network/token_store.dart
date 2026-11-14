import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the JWT pair is kept between requests. Desktop builds back it with
/// the OS keychain (macOS Keychain, Windows Credential Manager, libsecret on
/// Linux); tests use an in-memory stand-in.
abstract interface class TokenStore {
  Future<String?> readAccess();

  Future<String?> readRefresh();

  Future<void> save({required String access, required String refresh});

  Future<void> clear();
}

/// OS-backed storage. Never SharedPreferences or a plain file: an access
/// token is a password for the whole company's data.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _accessKey = 'cpms.access';
  static const _refreshKey = 'cpms.refresh';

  @override
  Future<String?> readAccess() => _storage.read(key: _accessKey);

  @override
  Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  @override
  Future<void> save({required String access, required String refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
