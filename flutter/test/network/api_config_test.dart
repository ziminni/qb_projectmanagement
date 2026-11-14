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
    test('the HTTP repositories stay off until USE_API is set', () {
      // Mocks stay the default: only `--dart-define=USE_API=true` swaps in the
      // HTTP repositories, so a test or demo run never reaches the server.
      expect(useApi, isFalse);
    });
  });
}
