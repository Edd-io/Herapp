import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Go library built by hook/build.dart (asset package:herapp/wireguard.dart).
@Native<Pointer<Utf8> Function(Pointer<Utf8>)>(symbol: 'WgStart')
external Pointer<Utf8> _wgStart(Pointer<Utf8> config);

@Native<Void Function()>(symbol: 'WgStop')
external void _wgStop();

@Native<Void Function(Pointer<Utf8>)>(symbol: 'WgFree')
external void _wgFree(Pointer<Utf8> p);

/// Starts the tunnel; returns the local proxy port or "error: …".
String _start(String config) {
  final c = config.toNativeUtf8();
  try {
    final r = _wgStart(c);
    final s = r.toDartString();
    _wgFree(r);
    return s;
  } finally {
    malloc.free(c);
  }
}

// Native calls run in a separate isolate (endpoint DNS resolution blocks).
// Top-level functions: a closure created inside Vpn would capture its context, which can't be sent.
Future<String> _startAsync(String config) => Isolate.run(() => _start(config));
Future<void> _stopAsync() => Isolate.run(_stopSync);
void _stopSync() => _wgStop();

final vpn = Vpn();

/// The app's secrets store. On macOS the file-based keychain: the data protection one needs a signing
/// team's keychain-access-groups entitlement, and fails with -34018 without it.
const secureStorage = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));

/// In-app WireGuard tunnel: every `HttpClient` goes through the tunnel's local proxy.
/// Tunnel on but not (yet) connected = traffic blocked, never sent in the clear.
class Vpn extends ChangeNotifier {
  static const _store = secureStorage; // the config contains a private key
  String? config;
  String name = '';
  bool enabled = false;
  bool running = false;
  bool unsupported = false; // native library missing on this platform
  String? error;
  Future<void> _queue = Future.value();

  Future<void> load() async {
    config = await _store.read(key: 'wg_config');
    name = await _store.read(key: 'wg_name') ?? '';
    enabled = config != null && await _store.read(key: 'wg_enabled') == '1';
    if (enabled) {
      HttpOverrides.global = _Proxy(null); // blocked right away, not after the first frame's requests
      apply();
    }
  }

  /// Completes once pending tunnel changes are applied (connected, failed or off).
  Future<void> get ready => _queue;

  /// Roughly validates then stores a wg-quick config (.conf).
  Future<void> import(String fileName, String text) async {
    if (!text.contains('[Interface]') || !text.contains('[Peer]')) {
      throw const FormatException('not a WireGuard config');
    }
    config = text;
    name = fileName;
    await _store.write(key: 'wg_config', value: text);
    await _store.write(key: 'wg_name', value: fileName);
    notifyListeners();
    if (enabled) await apply();
  }

  Future<void> setEnabled(bool v) async {
    enabled = v && config != null;
    await _store.write(key: 'wg_enabled', value: enabled ? '1' : '0');
    await apply();
  }

  Future<void> remove() async {
    config = null;
    name = '';
    for (final k in ['wg_config', 'wg_name', 'wg_enabled']) {
      await _store.delete(key: k);
    }
    await setEnabled(false);
  }

  /// (Re)starts or stops the tunnel according to the current state, one operation at a time.
  Future<void> apply() => _queue = _queue.then((_) async {
    running = false;
    unsupported = false;
    error = null;
    HttpOverrides.global = enabled ? _Proxy(null) : null; // block while connecting
    notifyListeners();
    try {
      await _stopAsync();
      if (!enabled) return;
      final r = await _startAsync(config!);
      final port = int.tryParse(r);
      if (port == null) {
        error = r.replaceFirst('error: ', '');
      } else {
        running = true;
        HttpOverrides.global = _Proxy(port);
      }
    } catch (e) {
      // library missing: platform not handled by hook/build.dart
      unsupported = true;
      debugPrint('WireGuard unavailable: $e');
    }
    notifyListeners();
  });
}

class _Proxy extends HttpOverrides {
  _Proxy(this.port);
  final int? port;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      // port 9 (discard): no connection possible, acts as a kill switch
      super.createHttpClient(context)..findProxy = (_) => 'PROXY 127.0.0.1:${port ?? 9}';
}
