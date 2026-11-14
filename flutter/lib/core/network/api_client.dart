import 'dart:typed_data';

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
          // Defence in depth: nothing carries the token off the API origin,
          // even a request built without going through [_run].
          if (!_isApiOrigin(options.uri)) {
            handler.reject(
              DioException(
                requestOptions: options,
                error: const BusinessRuleException(
                  'The server sent a link to a different site, so the request '
                  'was not sent.',
                ),
              ),
              true,
            );
            return;
          }
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

  /// The active role as the server sees it (sent as `X-Active-Role`), so a
  /// repository can tell an omitted finance key from a broken response.
  bool get seesFinance => _session.activeRole?.seesFinance ?? false;

  Future<Object?> get(
    String path, {
    Map<String, dynamic>? query,
    bool notFoundAsNull = false,
  }) => _run('GET', path, query: query, notFoundAsNull: notFoundAsNull);

  Future<Object?> post(String path, {Object? body}) =>
      _run('POST', path, body: body);

  Future<Object?> patch(String path, {Object? body}) =>
      _run('PATCH', path, body: body);

  /// Whole-set replaces: Phase 2 `PUT users/{id}/assignments/`.
  Future<Object?> put(String path, {Object? body}) =>
      _run('PUT', path, body: body);

  /// Only trades have a delete in Phase 1 (`DELETE master-data/trades/{id}/`).
  Future<Object?> delete(String path) => _run('DELETE', path);

  /// A private file (document or site photo) as bytes. [pathOrUrl] may be the
  /// absolute `file_url` the server sent; the JWT still travels in the
  /// `Authorization` header, never in the URL, and never off the API origin.
  Future<Uint8List> getBytes(String pathOrUrl) async {
    final data = await _run('GET', pathOrUrl, responseType: ResponseType.bytes);
    return Uint8List.fromList(data! as List<int>);
  }

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

  /// Redirects one request may follow, each of them re-checked for its origin.
  static const int _maxRedirects = 3;

  /// Sends one request and returns its data. The URL is resolved against the
  /// configured base and must stay on that origin (scheme, host, effective
  /// port): an absolute `file_url` or pagination `next` pointing elsewhere is
  /// refused before anything leaves the app, and redirects are followed by
  /// hand so every hop passes the same check — the JWT never reaches a host
  /// the base URL did not name.
  Future<Object?> _run(
    String method,
    String pathOrUrl, {
    Map<String, dynamic>? query,
    Object? body,
    ResponseType? responseType,
    bool notFoundAsNull = false,
  }) async {
    var path = _sameOriginPath(pathOrUrl);
    try {
      for (var hop = 0; ; hop++) {
        final first = hop == 0;
        final response = await _send(
          () => _dio.request<Object?>(
            path,
            data: first ? body : null,
            queryParameters: first ? query : null,
            options: Options(
              method: method,
              responseType: responseType,
              // A redirect is read here, not by the socket, so its target can
              // be checked before the token is attached again.
              validateStatus: (status) => status != null && status < 400,
            ),
          ),
        );
        final location = _redirectLocation(response, method);
        if (location == null) return response.data;
        if (hop == _maxRedirects) {
          throw const BusinessRuleException(
            'The server redirected this request too many times.',
          );
        }
        path = _sameOriginPath(location, previous: response.requestOptions.uri);
      }
    } on DioException catch (error) {
      if (notFoundAsNull && error.response?.statusCode == 404) return null;
      throw _businessError(error);
    }
  }

  /// The redirect to follow, or null when [response] is a normal answer.
  static String? _redirectLocation(Response<Object?> response, String method) {
    final status = response.statusCode ?? 0;
    if (status < 300 || status >= 400) return null;
    final location = response.headers.value('location');
    if (location == null || location.isEmpty) return null;
    if (method != 'GET') {
      // Replaying a write elsewhere is never what the server meant.
      throw const BusinessRuleException(
        'The server redirected this request, so it was not sent again.',
      );
    }
    return location;
  }

  /// The string handed to dio: a relative path stays relative (dio joins it to
  /// `baseUrl`), an absolute or protocol-relative URL is only accepted on the
  /// configured API origin. [previous] is the URL a redirect came from, so a
  /// relative `Location` resolves the way RFC 9110 says.
  String _sameOriginPath(String pathOrUrl, {Uri? previous}) {
    final uri = Uri.tryParse(pathOrUrl);
    if (uri == null) {
      throw const BusinessRuleException(
        'That link cannot be read, so the request was not sent.',
      );
    }
    final relative = !uri.hasScheme && !pathOrUrl.startsWith('//');
    if (relative && previous == null) return pathOrUrl;
    final target = (previous ?? _base).resolveUri(uri);
    if (!_isApiOrigin(target)) {
      throw const BusinessRuleException(
        'The server sent a link to a different site, so the request was not '
        'sent.',
      );
    }
    return target.toString();
  }

  /// The configured API base, with a trailing slash so relative URLs resolve
  /// inside it (`base/users/`, never `base/../users/`).
  Uri get _base {
    final base = Uri.parse(_dio.options.baseUrl);
    return base.path.endsWith('/') ? base : base.replace(path: '${base.path}/');
  }

  /// Scheme, host and effective port all match the configured API base.
  bool _isApiOrigin(Uri uri) {
    final base = _base;
    return uri.scheme.toLowerCase() == base.scheme.toLowerCase() &&
        uri.host.toLowerCase() == base.host.toLowerCase() &&
        uri.port == base.port;
  }

  Future<void> storeTokens({required String access, required String refresh}) =>
      _tokens.save(access: access, refresh: refresh);

  Future<void> clearTokens() => _tokens.clear();

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
    final cause = error.error;
    if (cause is BusinessRuleException) return cause;
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
