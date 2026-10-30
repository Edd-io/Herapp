import 'dart:io';

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
}
