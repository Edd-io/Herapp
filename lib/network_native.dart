import 'dart:convert';
import 'dart:io';

import 'network_types.dart';

NetworkClient createNetworkClient() => _NativeClient();

class _NativeClient implements NetworkClient {
  // A fresh client honors WireGuard's current HttpOverrides.
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  @override
  Future<NetworkResponse> request(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Map<String, String> cookies = const {},
    String? body,
  }) async {
    final req = await _client.openUrl(method, url);
    headers.forEach(req.headers.set);
    req.cookies.addAll(cookies.entries.map((e) => Cookie(e.key, e.value)));
    if (body != null) req.write(body);
    final res = await req.close();
    return (
      status: res.statusCode,
      body: await res.transform(utf8.decoder).join(),
      cookies: {for (final c in res.cookies) c.name: c.value},
    );
  }

  @override
  void close() => _client.close(force: true);
}

Future<NetworkSocket> openNetworkSocket(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final ws = await WebSocket.connect(url.toString(), customClient: client).timeout(const Duration(seconds: 15));
    ws.pingInterval = const Duration(seconds: 30);
    return _NativeSocket(ws);
  } finally {
    // The upgraded connection is detached from this HTTP client.
    client.close(force: true);
  }
}

class _NativeSocket implements NetworkSocket {
  _NativeSocket(this.ws);
  final WebSocket ws;
  @override
  Stream<dynamic> get stream => ws;
  @override
  int? get closeCode => ws.closeCode;
  @override
  void add(dynamic data) => ws.add(data);
  @override
  void close() => ws.close();
}
