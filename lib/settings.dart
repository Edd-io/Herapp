import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_localizations.dart';
import 'wireguard.dart';

final settings = Settings();

/// Persisted settings, read synchronously after [load].
class Settings extends ChangeNotifier {
  late SharedPreferences _p;

  Future<void> load() async => _p = await SharedPreferences.getInstance();

  ThemeMode get theme => ThemeMode.values[_p.getInt('theme') ?? 0];
  set theme(ThemeMode v) => _save(_p.setInt('theme', v.index));

  bool get haptics => _p.getBool('haptics') ?? true;
  set haptics(bool v) => _save(_p.setBool('haptics', v));

  /// Last chosen model, used as the default for new chats.
  String get model => _p.getString('model') ?? '';
  set model(String v) => _save(_p.setString('model', v));

  /// Hermes server address, read by hermes.dart once hooked up.
  String get url => _p.getString('url') ?? '';
  set url(String v) => _save(_p.setString('url', v.trim()));

  void _save(Future<bool> _) => notifyListeners();

  void haptic() {
    if (haptics) HapticFeedback.lightImpact();
  }
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final url = TextEditingController(text: settings.url);
  String? importError;
  bool testing = false;
  (bool ok, String text)? testResult;

  /// GET on the server URL; any HTTP response means reachable (Hermes API not known yet).
  Future<void> testServer() async {
    final l = AppLocalizations.of(context);
    final uri = Uri.tryParse(settings.url);
    if (uri == null || !uri.isScheme('http') && !uri.isScheme('https') || uri.host.isEmpty) {
      setState(() => testResult = (false, l.serverInvalidUrl));
      return;
    }
    if (vpn.enabled && !vpn.running) {
      setState(() => testResult = (false, l.serverBlocked)); // kill switch would refuse anyway
      return;
    }
    setState(() => testing = true);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    final sw = Stopwatch()..start();
    (bool, String) result;
    try {
      final res = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 15));
      await res.drain<void>();
      final text = l.serverReachable(res.statusCode, sw.elapsedMilliseconds);
      result = (true, vpn.running ? '$text · ${l.viaWireguard}' : text);
    } on TimeoutException {
      result = (false, l.serverUnreachable(l.serverTimeout));
    } on SocketException catch (e) {
      result = (false, l.serverUnreachable(e.osError?.message ?? e.message));
    } catch (e) {
      result = (false, l.serverUnreachable('$e'));
    } finally {
      client.close(force: true);
    }
    if (mounted) {
      setState(() {
        testing = false;
        testResult = result;
      });
    }
  }

  Future<void> importConfig() async {
    final f = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'WireGuard', extensions: ['conf'], uniformTypeIdentifiers: ['public.item']),
      ],
    );
    if (f == null) return;
    try {
      await vpn.import(f.name, await f.readAsString());
      setState(() => importError = null);
    } on Exception catch (e) {
      setState(() => importError = e is FormatException ? AppLocalizations.of(context).wgInvalidFile : '$e');
    }
  }

  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final label = TextStyle(fontSize: 17, color: c.onSurface);
    Widget section(String title, List<Widget> children, {String? footer}) => CupertinoListSection.insetGrouped(
      backgroundColor: c.surface,
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      separatorColor: c.outline.withValues(alpha: .2),
      header: Text(title.toUpperCase(), style: TextStyle(fontSize: 13, color: c.outline)),
      footer: footer == null ? null : Text(footer, style: TextStyle(fontSize: 13, color: c.outline)),
      children: children,
    );

    return Material(
      color: c.surface,
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([settings, vpn]),
          builder: (context, _) => ListView(
            children: [
              SizedBox(
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      l.settings,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                    ),
                    Positioned(
                      right: 4,
                      child: CupertinoButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'OK',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              section(l.appearance, [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: CupertinoSlidingSegmentedControl<ThemeMode>(
                    groupValue: settings.theme,
                    thumbColor: c.surface,
                    backgroundColor: c.surfaceContainerLow,
                    onValueChanged: (v) => settings.theme = v!,
                    children: {
                      for (final (m, l) in [
                        (ThemeMode.system, l.themeSystem),
                        (ThemeMode.light, l.themeLight),
                        (ThemeMode.dark, l.themeDark),
                      ])
                        m: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(l, style: TextStyle(fontSize: 15, color: c.onSurface)),
                        ),
                    },
                  ),
                ),
              ]),
              section(l.general, [
                CupertinoListTile(
                  title: Text(l.haptics, style: label),
                  trailing: CupertinoSwitch(value: settings.haptics, onChanged: (v) => settings.haptics = v),
                ),
              ]),
              section(l.hermesServer, [
                CupertinoListTile(
                  title: CupertinoTextField.borderless(
                    controller: url,
                    placeholder: 'https://hermes.example.com',
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    padding: EdgeInsets.zero,
                    style: label,
                    onChanged: (v) {
                      settings.url = v;
                      if (testResult != null) setState(() => testResult = null);
                    },
                  ),
                ),
                CupertinoListTile(
                  title: Text(l.serverTest, style: label),
                  subtitle: testResult == null
                      ? null
                      : Text(
                          testResult!.$2,
                          maxLines: 3,
                          style: TextStyle(color: testResult!.$1 ? CupertinoColors.systemGreen : CupertinoColors.systemRed),
                        ),
                  trailing: testing ? const CupertinoActivityIndicator() : null,
                  onTap: testing ? null : testServer,
                ),
              ], footer: l.hermesServerFooter),
              section(l.wireguard, [
                CupertinoListTile(
                  title: Text(l.wgConfig, style: label),
                  additionalInfo: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .45),
                    child: Text(
                      vpn.config == null ? l.wgImport : vpn.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.outline),
                    ),
                  ),
                  trailing: const CupertinoListTileChevron(),
                  onTap: importConfig,
                ),
                CupertinoListTile(
                  title: Text(l.wgUse, style: label),
                  subtitle: !vpn.enabled
                      ? null
                      : Text(
                          vpn.running
                              ? l.wgConnected
                              : vpn.unsupported
                              ? l.wgUnavailable
                              : vpn.error != null
                              ? l.wgError(vpn.error!)
                              : l.wgConnecting,
                          style: TextStyle(
                            color: vpn.running
                                ? CupertinoColors.systemGreen
                                : vpn.error != null
                                ? CupertinoColors.systemRed
                                : c.outline,
                          ),
                        ),
                  trailing: CupertinoSwitch(value: vpn.enabled, onChanged: vpn.config == null ? null : vpn.setEnabled),
                ),
                if (vpn.config != null)
                  CupertinoListTile(
                    title: Text(l.wgRemove, style: TextStyle(fontSize: 17, color: CupertinoColors.systemRed)),
                    onTap: vpn.remove,
                  ),
              ], footer: importError ?? l.wgFooter),
            ],
          ),
        ),
      ),
    );
  }
}
