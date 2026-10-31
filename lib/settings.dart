import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'wireguard.dart';

final settings = Settings();

/// Persisted settings, read synchronously after [load].
class Settings extends ChangeNotifier {
  late SharedPreferences _p;
  static const _secure = FlutterSecureStorage();

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    password = await _secure.read(key: 'hermes_password') ?? '';
  }

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

  bool get auth => _p.getBool('auth') ?? false;
  set auth(bool v) => _save(_p.setBool('auth', v));

  String get user => _p.getString('user') ?? '';
  set user(String v) => _save(_p.setString('user', v.trim()));

  /// Kept in the Keychain, not in preferences.
  String password = '';
  Future<void> setPassword(String v) {
    password = v;
    return _secure.write(key: 'hermes_password', value: v);
  }

  void _save(Future<bool> _) => notifyListeners();

  void haptic() {
    if (haptics) HapticFeedback.lightImpact();
  }
}

/// Catalog and quotas of the configured server, through the tunnel once it's ready; null if no server is set.
Future<ModelOptions?> serverOptions() async {
  final base = Uri.tryParse(settings.url);
  if (base == null || !base.hasAuthority) return null;
  if (vpn.enabled) await vpn.ready; // don't race the tunnel at startup
  return fetchModels(base, user: settings.auth ? settings.user : null, password: settings.password).timeout(const Duration(seconds: 20));
}

/// REST call to the configured server, through the tunnel; null if no server is set.
/// [body] is sent as JSON.
Future<String?> serverApi(String method, String path, {Object? body}) async {
  final base = Uri.tryParse(settings.url);
  if (base == null || !base.hasAuthority) return null;
  if (vpn.enabled) await vpn.ready;
  return callApi(
    base,
    method,
    path,
    body: body,
    user: settings.auth ? settings.user : null,
    password: settings.password,
  ).timeout(const Duration(seconds: 20));
}

Future<Gateway?>? _gateway;

/// The shared chat connection to the configured server, reopened once lost; null if no server is set.
Future<Gateway?> gateway() async {
  final current = _gateway;
  if (current != null) {
    final g = await current.catchError((Object _) => null);
    if (g != null && !g.closed) return g;
    if (!identical(_gateway, current)) return gateway(); // another caller is already reconnecting
  }
  return (_gateway = () async {
    final base = Uri.tryParse(settings.url);
    if (base == null || !base.hasAuthority) return null;
    if (vpn.enabled) await vpn.ready;
    return connectGateway(
      base,
      user: settings.auth ? settings.user : null,
      password: settings.password,
    ).timeout(const Duration(seconds: 20));
  }());
}

/// Closes the chat connection, e.g. after the server, sign-in or tunnel changed.
void dropGateway() {
  _gateway?.then((g) => g?.close(), onError: (Object _) {});
  _gateway = null;
}

/// User-facing text for a [serverOptions] failure; null [e] = no server set.
String serverErrorText(AppLocalizations l, Object? e) => switch (e) {
  null => l.serverNotSet,
  // Hermes updated on disk but not restarted: it refuses to list models
  HttpException(:final message) when message.startsWith('Restart required') => l.serverRestart,
  HttpException(:final message) => l.serverLoadFailed(message),
  _ => l.serverLoadFailed('$e'),
};

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final url = TextEditingController(text: settings.url);
  final user = TextEditingController(text: settings.user);
  final password = TextEditingController(text: settings.password);
  String? importError;
  bool testing = false;
  (bool ok, String text)? testResult;

  /// Checks the URL answers like a Hermes server (GET /api/status, no auth needed).
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
      final res = await (await client.getUrl(hermesStatusUri(uri))).close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      final st = res.statusCode == 200 ? hermesStatus(body) : null;
      if (st == null) {
        result = (false, l.serverNotHermes(res.statusCode));
      } else if (!settings.auth) {
        result = st.authRequired ? (false, l.serverAuthRequired(st.version)) : (true, l.serverHermes(st.version, sw.elapsedMilliseconds));
      } else {
        final r = await hermesLogin(client, uri, settings.user, settings.password).timeout(const Duration(seconds: 15));
        result = switch (r.status) {
          _ when r.ok => (true, l.serverAuthOk(st.version, sw.elapsedMilliseconds)),
          401 => (false, l.serverAuthRejected(st.version)),
          429 => (false, l.serverAuthRateLimited(st.version)),
          _ => (false, l.serverAuthFailed(st.version, r.status)),
        };
      }
      if (vpn.running) result = (result.$1, '${result.$2} · ${l.viaWireguard}');
    } on TimeoutException {
      result = (false, l.serverUnreachable(l.serverTimeout));
    } on HttpException catch (e) {
      // "Proxy failed to establish tunnel" = our WireGuard proxy answered 502
      result = (false, l.serverUnreachable(e.message.contains('Proxy failed') ? l.serverTunnelFailed : e.message));
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

  void clearTest() {
    if (testResult != null) setState(() => testResult = null);
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
    user.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final label = TextStyle(fontSize: 17, color: c.onSurface);
    Widget section(String title, List<Widget> children, {String? footer, (bool, String)? status}) => CupertinoListSection.insetGrouped(
      backgroundColor: c.surface,
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      separatorColor: c.outline.withValues(alpha: .2),
      header: Text(title.toUpperCase(), style: TextStyle(fontSize: 13, color: c.outline)),
      footer: footer == null && status == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // status line (e.g. connection test result) sits above the hint, outside the card
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      status.$2,
                      style: TextStyle(fontSize: 13, color: status.$1 ? CupertinoColors.systemGreen : CupertinoColors.systemRed),
                    ),
                  ),
                if (footer != null) Text(footer, style: TextStyle(fontSize: 13, color: c.outline)),
              ],
            ),
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
              section(
                l.hermesServer,
                [
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
                        clearTest();
                      },
                    ),
                  ),
                  CupertinoListTile(
                    title: Text(l.hermesAuth, style: label),
                    trailing: CupertinoSwitch(
                      value: settings.auth,
                      onChanged: (v) {
                        settings.auth = v;
                        clearTest();
                      },
                    ),
                  ),
                  if (settings.auth) ...[
                    CupertinoListTile(
                      title: CupertinoTextField.borderless(
                        controller: user,
                        placeholder: l.hermesUser,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.none,
                        padding: EdgeInsets.zero,
                        style: label,
                        onChanged: (v) {
                          settings.user = v;
                          clearTest();
                        },
                      ),
                    ),
                    CupertinoListTile(
                      title: CupertinoTextField.borderless(
                        controller: password,
                        placeholder: l.hermesPassword,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        padding: EdgeInsets.zero,
                        style: label,
                        onChanged: (v) {
                          settings.setPassword(v);
                          clearTest();
                        },
                      ),
                    ),
                  ],
                  CupertinoListTile(
                    title: Text(l.serverTest, style: label),
                    trailing: testing ? const CupertinoActivityIndicator() : null,
                    onTap: testing ? null : testServer,
                  ),
                ],
                footer: l.hermesServerFooter,
                status: testResult,
              ),
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
