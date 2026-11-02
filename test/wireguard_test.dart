import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/wireguard.dart';

// Separate file: the testWidgets environment interferes with the real networking used here.
void main() {
  test('native tunnel: invalid config rejected, traffic blocked until connected', () async {
    vpn
      ..config = '[Interface]\n[Peer]\n'
      ..enabled = true;
    await vpn.apply();
    expect(vpn.running, isFalse);
    expect(vpn.error, contains('missing Address')); // message from Go via FFI
    // kill switch: the connection targets the local blocking proxy, never the destination
    await expectLater(
      HttpClient().getUrl(Uri.parse('http://10.255.255.1/')),
      throwsA(isA<SocketException>().having((e) => e.address?.address, 'adresse', '127.0.0.1')),
    );

    vpn.enabled = false;
    await vpn.apply();
    expect(HttpOverrides.current, isNull);
  });
  test('back from the background, the tunnel starts afresh', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({'wg_config': '[Interface]\n[Peer]\n', 'wg_enabled': '1'});
    await vpn.load();
    await vpn.ready;
    vpn.error = null;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); // a glance at the notifications: kept
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await vpn.ready;
    expect(vpn.error, isNull);
    for (final st in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(st);
    }
    await vpn.ready;
    expect(vpn.error, contains('missing Address'));
    await vpn.setEnabled(false);
  });
}
