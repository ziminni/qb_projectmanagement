import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Set it at build time:
/// `flutter run -d linux --dart-define=API_BASE_URL=https://cpms.example.ph/api/v1`
const String _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');

/// Where the CPMS compose stack serves the API on a developer machine.
const String _debugApiBaseUrl = 'http://127.0.0.1:8001/api/v1';

/// Backend base URL. A debug build without `API_BASE_URL` talks to the local
/// compose backend; a release build must be told where the server is.
String get apiBaseUrl =>
    resolveApiBaseUrl(configured: _configuredApiBaseUrl, debug: kDebugMode);

String resolveApiBaseUrl({required String configured, required bool debug}) {
  if (configured.isNotEmpty) return configured;
  if (debug) return _debugApiBaseUrl;
  throw StateError(
    'API_BASE_URL is not set. Build the release with '
    '--dart-define=API_BASE_URL=https://<host>/api/v1',
  );
}

/// Dio joins a relative path onto the base by plain concatenation, so a base
/// without a trailing slash turns `users/` into `/api/v1users/`.
String withTrailingSlash(String base) => base.endsWith('/') ? base : '$base/';

const String _configuredUseApi = String.fromEnvironment('USE_API');

bool get _isFlutterTest =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// Live HTTP repositories are the default on `flutter run` (`USE_API` unset or
/// `true`). Pass `--dart-define=USE_API=false` for offline mock mode; unit and
/// widget tests (`FLUTTER_TEST`) keep mocks by default unless `USE_API=true`
/// is passed explicitly.
bool resolveUseApi({required String configured, required bool isTest}) {
  final normalized = configured.trim().toLowerCase();
  if (normalized == 'true' || normalized == '1') return true;
  if (normalized == 'false' || normalized == '0') return false;
  return !isTest;
}

bool get useApi =>
    resolveUseApi(configured: _configuredUseApi, isTest: _isFlutterTest);
