bool get macCapable => false;

/// Local execution is unavailable in a browser. Remote tools still run on Hermes.
class MacShell {
  static String get home => '/';
  static String get shell => '';
  String cwd = '/';
  bool get busy => false;
  void stop([String why = 'stopped by the user']) {}
  String note(String token, {String folder = '', bool here = false}) => '';
  Future<(int, String)> run(String script, void Function(String) onOut, {Duration timeout = const Duration(minutes: 10)}) async =>
      throw UnsupportedError('Local commands require the native app');
  (int, String) write(String path, String content) => throw UnsupportedError('Local files require the native app');
}
