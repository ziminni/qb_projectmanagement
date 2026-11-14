import 'package:dio/dio.dart';

import '../../data/models/app_role.dart';
import '../../data/services/business_rule_exception.dart';
import '../../data/services/session_service.dart';
import 'api_config.dart';
import 'token_store.dart';

/// One HTTP client for the whole app. It attaches the JWT and the active
/// role, refreshes the token once when it expires (then signs out), and turns
/// every failure into a [BusinessRuleException] carrying the server's own
/// message so the screens show one kind of error.
class ApiClient {
  ApiClient({
    required TokenStore tokens,
    required SessionService session,
    Dio? dio,
  }) : _tokens = tokens,
       _session = session,
       _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = apiBaseUrl
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers['Accept'] = Headers.jsonContentType
      ..contentType = Headers.jsonContentType;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final access = await _tokens.readAccess();
          if (access != null) {
            options.headers['Authorization'] = 'Bearer $access';
          }
          final role = _session.activeRole;
          if (role != null) {
            options.headers['X-Active-Role'] = role.apiValue;
          }
          handler.next(options);
        },
      ),
    );
  }

  final TokenStore _tokens;
  final SessionService _session;
  final Dio _dio;

  /// The refresh in flight, so ten failing requests share one refresh.
  Future<void>? _refreshing;

  Future<Object?> get(
    String path, {
    Map<String, dynamic>? query,
    bool notFoundAsNull = false,
  }) => _run(
    () => _dio.get<Object?>(path, queryParameters: query),
    notFoundAsNull: notFoundAsNull,
  );

  Future<Object?> post(String path, {Object? body}) =>
      _run(() => _dio.post<Object?>(path, data: body));

  Future<Object?> patch(String path, {Object? body}) =>
      _run(() => _dio.patch<Object?>(path, data: body));

  /// Only trades have a delete in Phase 1 (`DELETE master-data/trades/{id}/`).
  Future<Object?> delete(String path) => _run(() => _dio.delete<Object?>(path));

  /// Reads every row of a DRF list, following `next` to the last page.
  /// A list that never ends is refused rather than looping forever.
  Future<List<Map<String, dynamic>>> getRows(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final rows = <Map<String, dynamic>>[];
    Object? page = await get(path, query: query);
    for (var fetched = 1; ; fetched++) {
      rows.addAll(jsonRows(page));
      final next = page is Map ? page['next'] : null;
      if (next is! String || next.isEmpty) return rows;
      if (fetched == _maxListPages) {
        throw const BusinessRuleException(
          'This list has too many pages to load. Narrow the search.',
        );
      }
      page = await get(next);
    }
  }

  /// Pages the client will read before giving up on a runaway list.
  static const int _maxListPages = 200;

  Future<void> storeTokens({required String access, required String refresh}) =>
      _tokens.save(access: access, refresh: refresh);

  Future<void> clearTokens() => _tokens.clear();

  Future<Object?> _run(
    Future<Response<Object?>> Function() send, {
    bool notFoundAsNull = false,
  }) async {
    try {
      return (await _send(send)).data;
    } on DioException catch (error) {
      if (notFoundAsNull && error.response?.statusCode == 404) return null;
      throw _businessError(error);
    }
  }

  /// Sends the request; a 401 gets one token refresh and one retry.
  Future<Response<Object?>> _send(
    Future<Response<Object?>> Function() send, {
    bool mayRefresh = true,
  }) async {
    try {
      return await send();
    } on DioException catch (error) {
      if (mayRefresh && error.response?.statusCode == 401) {
        await _refreshOnce();
        return _send(send, mayRefresh: false);
      }
      rethrow;
    }
  }

  Future<void> _refreshOnce() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<void> _doRefresh() async {
    final refresh = await _tokens.readRefresh();
    if (refresh == null) return _expire();
    try {
      final response = await _dio.post<Object?>(
        'auth/refresh/',
        data: {'refresh': refresh},
      );
      final data = jsonObject(response.data);
      final access = data['access'];
      if (access is! String) {
        // An answer without an access token is as good as an expiry.
        await _expire();
        return;
      }
      await _tokens.save(
        access: access,
        refresh: (data['refresh'] ?? refresh) as String,
      );
    } on DioException {
      // The refresh token is dead too: forget both and send the user back to
      // the login screen (the router listens to SessionService).
      await _expire();
    }
  }

  Future<void> _expire() async {
    await _tokens.clear();
    _session.signOut();
    throw const BusinessRuleException(
      'Your session has expired. Sign in again.',
    );
  }

  BusinessRuleException _businessError(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return BusinessRuleException(data['detail'] as String);
    }
    return BusinessRuleException(switch (error.response?.statusCode) {
      int status when status >= 500 =>
        'The server could not complete the request. Try again.',
      400 || 422 => 'Some details were not accepted. Check the values.',
      401 => 'Your session has expired. Sign in again.',
      403 => 'Your account is not allowed to do that.',
      404 => 'That record no longer exists.',
      null => 'Cannot reach the server. Check your connection.',
      final status => 'The server refused the request ($status).',
    });
  }
}

/// Django REST lists are either bare lists or `{count, results}` pages.
List<Map<String, dynamic>> jsonRows(Object? data) {
  final rows = data is Map<String, dynamic> ? data['results'] : data;
  return [
    for (final row in (rows as List<dynamic>? ?? const []))
      (row as Map).cast<String, dynamic>(),
  ];
}

Map<String, dynamic> jsonObject(Object? data) =>
    (data as Map).cast<String, dynamic>();

/// The wire sends a role as its code or as a whole `user_roles` row.
AppRole roleFrom(Object? raw) =>
    raw is Map ? AppRole.fromJson(raw['role']) : AppRole.fromJson(raw);
