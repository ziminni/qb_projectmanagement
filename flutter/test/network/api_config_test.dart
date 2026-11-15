import 'package:buildpro_frontend/core/network/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('api base url', () {
    test('uses the build-time URL when one is given', () {
      expect(
        resolveApiBaseUrl(
          configured: 'https://cpms.example.ph/api/v1',
          debug: true,
        ),
        'https://cpms.example.ph/api/v1',
      );
      expect(
        resolveApiBaseUrl(
          configured: 'https://cpms.example.ph/api/v1',
          debug: false,
        ),
        'https://cpms.example.ph/api/v1',
      );
    });

    test('falls back to the local CPMS backend in a debug build', () {
      expect(
        resolveApiBaseUrl(configured: '', debug: true),
        'http://127.0.0.1:8001/api/v1',
      );
    });

    test('refuses to start a release build with no API_BASE_URL', () {
      expect(
        () => resolveApiBaseUrl(configured: '', debug: false),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('API_BASE_URL'),
          ),
        ),
      );
    });
  });

  group('repository mode', () {
    test('defaults to live HTTP repositories on flutter run and mocks in flutter test', () {
      // Inside `flutter test` (`FLUTTER_TEST=true`) mocks stay the default so
      // unit/widget tests never hit a server unless `USE_API=true` is passed.
      expect(useApi, isFalse);
      // On `flutter run` (`isTest: false`), HTTP repositories are the default.
      expect(resolveUseApi(configured: '', isTest: false), isTrue);
      expect(resolveUseApi(configured: 'false', isTest: false), isFalse);
      expect(resolveUseApi(configured: 'true', isTest: true), isTrue);
    });
  });
}
