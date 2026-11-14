import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:buildpro_frontend/core/network/api_client.dart';
import 'package:buildpro_frontend/core/network/token_store.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/user.dart';
import 'package:buildpro_frontend/data/services/session_service.dart';
import 'package:dio/dio.dart';

/// Answers requests from [handler] and records them. No socket is opened, so
/// the client tests run without a live backend.
class FakeApi implements HttpClientAdapter {
  FakeApi(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  List<String> get paths => [for (final request in requests) request.path];

  int countOf(String path) => paths.where((p) => p == path).length;

  RequestOptions last(String path) =>
      requests.lastWhere((request) => request.path == path);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(Object? body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody noContent() => ResponseBody.fromString('', 204);

/// A private file's bytes (a document or a site photo).
ResponseBody bytesBody(List<int> body, {int status = 200}) =>
    ResponseBody.fromBytes(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/octet-stream'],
      },
    );

/// A `302` pointing at [location], as a proxy or Django's `APPEND_SLASH` would.
ResponseBody redirectTo(String location) => ResponseBody.fromString(
  '',
  302,
  headers: {
    'location': [location],
  },
);

/// The body a repository sent, decoded back into a map.
Map<String, dynamic> sentBody(RequestOptions options) =>
    (options.data as Map).cast<String, dynamic>();

const testAccess = 'access-1';
const testRefresh = 'refresh-1';

/// Stands in for the OS keychain in tests.
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore({this.access, this.refresh});

  String? access;
  String? refresh;
  int clearCalls = 0;

  @override
  Future<String?> readAccess() async => access;

  @override
  Future<String?> readRefresh() async => refresh;

  @override
  Future<void> save({required String access, required String refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
    clearCalls++;
  }
}

const testUser = User(
  id: 7,
  companyId: 1,
  fullName: 'Maria Santos',
  email: 'maria@example.ph',
);

/// A signed-in session holding [roles], with [active] as the active role.
SessionService signedInSession({
  List<AppRole> roles = const [AppRole.owner, AppRole.admin],
  AppRole? active,
}) {
  final session = SessionService();
  session.signIn(testUser, roles, activeRole: active);
  return session;
}

/// A client wired to [api] with tokens already stored.
ApiClient testClient({
  required FakeApi api,
  required InMemoryTokenStore tokens,
  SessionService? session,
}) {
  final dio = Dio()..httpClientAdapter = api;
  return ApiClient(
    tokens: tokens,
    session: session ?? signedInSession(),
    dio: dio,
  );
}
