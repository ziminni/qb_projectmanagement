import 'package:buildpro_frontend/core/network/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

void main() {
  test('a relative path stays inside /api/v1 (never /api/v1users/)', () async {
    final api = FakeApi((_) => json(<Object?>[]));
    final client = testClient(api: api, tokens: InMemoryTokenStore());

    await client.getRows('users/');

    expect(api.requests.single.uri.path, '/api/v1/users/');
  });

  test('withTrailingSlash adds one slash only when it is missing', () {
    expect(withTrailingSlash('https://h/api/v1'), 'https://h/api/v1/');
    expect(withTrailingSlash('https://h/api/v1/'), 'https://h/api/v1/');
  });
}
