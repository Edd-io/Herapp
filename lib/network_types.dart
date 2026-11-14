/// Cookies are managed by the browser on web, and explicitly on native platforms.
typedef NetworkResponse = ({int status, String body, Map<String, String> cookies});

abstract class NetworkClient {
  Future<NetworkResponse> request(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Map<String, String> cookies = const {},
    String? body,
  });
  void close();
}

abstract class NetworkSocket {
  Stream<dynamic> get stream;
  int? get closeCode;
  void add(dynamic data);
  void close();
}

/// Transport failure (including a request blocked by the browser's CORS policy).
class NetworkException implements Exception {
  const NetworkException(this.message);
  final String message;
  @override
  String toString() => message;
}
