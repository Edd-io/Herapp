import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'l10n/app_localizations.dart';
import 'settings.dart';

/// The device's own unlock (Face ID, Touch ID or its passcode); replaced in tests.
var deviceAuth = (
  available: () async => !kIsWeb && await LocalAuthentication().isDeviceSupported().catchError((Object _) => false),
  confirm: (String reason) => LocalAuthentication().authenticate(localizedReason: reason, persistAcrossBackgrounding: true),
);

/// Asks the device's unlock; false when refused or unavailable.
Future<bool> confirmOwner(String reason) async {
  try {
    return await deviceAuth.confirm(reason);
  } catch (e) {
    debugPrint('Unlock: $e');
    return false;
  }
}

/// Covers the app while [settings.lock] is on, from launch and each time it leaves the screen, until the
/// device's unlock lets the owner back in. On a phone the app switcher's snapshot is covered too.
class AppLock extends StatefulWidget {
  const AppLock({super.key, required this.child});
  final Widget child;

  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  late bool locked = !kIsWeb && settings.lock;
  bool veiled = false; // the app switcher's snapshot, on a phone
  bool asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (locked) WidgetsBinding.instance.addPostFrameCallback((_) => unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (kIsWeb || !settings.lock) return;
    final phone = const [TargetPlatform.iOS, TargetPlatform.android].contains(defaultTargetPlatform);
    switch (s) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        setState(() => locked = true);
      // the unlock prompt itself makes the app inactive: only a veil, never a lock, or it would ask forever
      case AppLifecycleState.inactive when phone && !asking:
        setState(() => veiled = true);
      case AppLifecycleState.resumed:
        setState(() => veiled = false);
        if (locked) unlock();
      default:
    }
  }

  Future<void> unlock() async {
    if (asking) return;
    asking = true;
    final ok = await confirmOwner(AppLocalizations.of(context).unlockReason);
    asking = false;
    if (ok && mounted) setState(() => locked = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Stack(
      children: [
        widget.child,
        if (locked || veiled)
          Positioned.fill(
            child: ColoredBox(
              color: c.surface,
              child: Center(
                child: locked
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.lock_fill, size: 48, color: c.onSurface),
                          const SizedBox(height: 16),
                          Hover(
                            radius: 10,
                            child: CupertinoButton(
                              onPressed: unlock,
                              child: Text(AppLocalizations.of(context).unlock, style: TextStyle(fontSize: 17, color: c.onSurface)),
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
