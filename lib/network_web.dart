import 'dart:convert';

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/html.dart';

import 'network_types.dart';

NetworkClient createNetworkClient() => _BrowserClient();

class _BrowserClient implements NetworkClient {
  final _client = BrowserClient()..withCredentials = true;

  @override
  Future<NetworkResponse> request(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Map<String, String> cookies = const {},
    String? body,
  }) async {
    try {
      final req = http.Request(method, url)..headers.addAll(headers);
      if (body != null) req.body = body;
      final res = await _client.send(req);
      // Cookie and Set-Cookie headers belong to the browser, including HttpOnly sessions.
      return (status: res.statusCode, body: await res.stream.transform(utf8.decoder).join(), cookies: const <String, String>{});
    } on http.ClientException catch (e) {
      throw NetworkException('Could not reach Hermes. Check the server URL, HTTPS and CORS configuration. ${e.message}');
    }
  }

  @override
  void close() => _client.close();
}

Future<NetworkSocket> openNetworkSocket(Uri url) async {
  final channel = HtmlWebSocketChannel.connect(url, binaryType: BinaryType.list);
  try {
    await channel.ready.timeout(const Duration(seconds: 15));
    return _BrowserSocket(channel);
  } catch (_) {
    channel.sink.close();
    throw const NetworkException('Could not open the Hermes WebSocket. Check WSS and the allowed origin.');
  }
}

class _BrowserSocket implements NetworkSocket {
  _BrowserSocket(this.channel);
  final HtmlWebSocketChannel channel;
  @override
  Stream<dynamic> get stream => channel.stream;
  @override
  int? get closeCode => channel.closeCode;
  @override
  void add(dynamic data) => channel.sink.add(data);
  @override
  void close() => channel.sink.close();
}
