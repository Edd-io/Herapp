import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const secureStorage = FlutterSecureStorage();
final vpn = Vpn();

/// A browser uses the system's network; it cannot host the native WireGuard tunnel.
class Vpn extends ChangeNotifier {
  String? get config => null;
  String get name => '';
  bool get enabled => false;
  bool get running => false;
  bool get unsupported => true;
  String? get error => null;
  bool get connecting => false;
  bool get tried => false;
  Future<void> get ready async {}
  Future<void> load([String server = '']) async {}
  Future<void> forget(String server) async {}
  Future<void> apply() async {}
  void reached() {}
  Future<void> import(String name, String text) async => throw UnsupportedError('WireGuard requires the native app or a system VPN');
  Future<void> setEnabled(bool enabled) async {
    if (enabled) throw UnsupportedError('WireGuard requires the native app or a system VPN');
  }

  Future<void> remove() async {}
}
