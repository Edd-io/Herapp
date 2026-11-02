import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'lock.dart';
import 'mac.dart';
import 'wireguard.dart';

final settings = Settings();

/// WCAG contrast ratio between [a] and [b] (1 to 21; text needs 4.5).
double contrast(Color a, Color b) {
  final [hi, lo] = [a.computeLuminance(), b.computeLuminance()]..sort((x, y) => y.compareTo(x));
  return (hi + .05) / (lo + .05);
}

/// The accent as a text color (links), when it reads on [c]'s background; null keeps the text's own.
Color? accentText(ColorScheme c) => settings.accent != 0 && contrast(c.primary, c.surface) >= 4.5 ? c.primary : null;

/// A segmented control's thumb: the accent when one is picked, else the plain surface.
Color segmentThumb(ColorScheme c) => settings.accent == 0 ? c.surface : c.primary;

/// A segment's label, readable on [segmentThumb] when it's the [selected] one.
Color segmentText(ColorScheme c, bool selected) => selected && settings.accent != 0 ? c.onPrimary : c.onSurface;

/// The accent colors to pick from, neutral first.
const accents = [0, 0xFF5E5CE6, 0xFF0A84FF, 0xFF30B0C7, 0xFF34C759, 0xFFFF9F0A, 0xFFFF375F, 0xFFC9A227];

/// Persisted settings, read synchronously after [load].
class Settings extends ChangeNotifier {
  late SharedPreferences _p;
  static const _secure = secureStorage;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    password = await _secure.read(key: 'hermes_password') ?? '';
  }

  ThemeMode get theme => ThemeMode.values[_p.getInt('theme') ?? 0];
  set theme(ThemeMode v) => _save(_p.setInt('theme', v.index));

  /// The accent color (send button, selection, links) as ARGB; 0 = the neutral black and white.
  int get accent => _p.getInt('accent') ?? 0;
  set accent(int v) => _save(_p.setInt('accent', v));

  /// Language code of the app's texts, '' to follow the device.
  String get language => _p.getString('language') ?? '';
  set language(String v) => _save(_p.setString('language', v));

  bool get haptics => _p.getBool('haptics') ?? true;
  set haptics(bool v) => _save(_p.setBool('haptics', v));

  /// Whether a reply done while the app is out of sight is told by a notification.
  bool get notifications => _p.getBool('notifications') ?? true;
  set notifications(bool v) => _save(_p.setBool('notifications', v));

  /// Whether the app asks the device's unlock (Face ID, Touch ID, passcode) to open.
  bool get lock => _p.getBool('lock') ?? false;
  set lock(bool v) => _save(_p.setBool('lock', v));

  /// Whether Hermes may ask this computer to run commands, through the chat (see mac.dart).
  bool get macShell => _p.getBool('macShell') ?? false;
  set macShell(bool v) => _save(_p.setBool('macShell', v));

  /// The secret in the blocks Hermes writes to run commands here, so that one quoted from elsewhere doesn't.
  String get macToken => switch (_p.getString('macToken')) {
    final t? => t,
    _ => (() {
      final t = Random.secure().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
      _p.setString('macToken', t);
      return t;
    })(),
  };

  /// Last chosen model, used as the default for new chats.
  String get model => _p.getString('model') ?? '';
  set model(String v) => _save(_p.setString('model', v));

  /// The models last picked, the latest first (5 at most).
  List<String> get recentModels => _p.getStringList('recentModels') ?? const [];
  void usedModel(String id) => _save(_p.setStringList('recentModels', {id, ...recentModels}.take(5).toList()));

  /// Last chosen reasoning effort ('' = the server's), used for new chats.
  String get effort => _p.getString('effort') ?? '';
  set effort(String v) => _save(_p.setString('effort', v));

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
  return _watch(
    fetchModels(base, user: settings.auth ? settings.user : null, password: settings.password).timeout(const Duration(seconds: 20)),
  );
}

/// Window width from which the app lays out for a computer or tablet: menu always shown, text column narrowed.
const wideWidth = 900.0;

/// [child] narrowed to a readable [width] and centered, on a wide window.
Widget readable(Widget child, {double width = 720}) => Align(
  alignment: Alignment.topCenter,
  child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: width),
    child: child,
  ),
);

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideWidth;

/// Lights up what the mouse points at, as desktop buttons do; touch screens never see it.
/// [label] names an icon-only button, for screen readers and as a tooltip.
class Hover extends StatefulWidget {
  const Hover({super.key, required this.child, this.radius = 10, this.label});
  final Widget child;
  final double radius; // of the highlight's corners; a large one makes a round button's circle
  final String? label;

  @override
  State<Hover> createState() => _HoverState();
}

class _HoverState extends State<Hover> {
  var on = false;

  @override
  Widget build(BuildContext context) {
    final lit = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => on = true),
      onExit: (_) => setState(() => on = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        foregroundDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: on ? .07 : 0),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: widget.child,
      ),
    );
    return widget.label == null ? lit : Tooltip(message: widget.label, child: lit);
  }
}

/// A floating window over a wide window's content, [width] wide at most, [height] tall when given.
Future<T?> _floating<T>(BuildContext context, WidgetBuilder builder, {double width = 560, double? height}) {
  final c = Theme.of(context).colorScheme;
  final screen = MediaQuery.sizeOf(context).height;
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .4),
    builder: (context) => Dialog(
      backgroundColor: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: screen * .85),
        child: height == null ? builder(context) : SizedBox(height: screen * height, child: builder(context)),
      ),
    ),
  );
}

/// A sheet up from the bottom on a phone, a floating window on a wide window.
Future<T?> showPanel<T>(BuildContext context, WidgetBuilder builder, {bool scrollControlled = false}) => isWide(context)
    ? _floating<T>(context, (context) => Padding(padding: const EdgeInsets.only(top: 20), child: builder(context)))
    : showModalBottomSheet<T>(
        context: context,
        isScrollControlled: scrollControlled,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        barrierColor: Colors.black.withValues(alpha: .4),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: builder,
      );

/// A full-height page sheet on a phone (settings), a tall floating window on a wide window.
Future<T?> showPageSheet<T>(BuildContext context, WidgetBuilder builder) =>
    isWide(context) ? _floating<T>(context, builder, width: 640, height: .85) : showCupertinoSheet<T>(context: context, builder: builder);

/// An action sheet: from the bottom on a phone, floating in the middle of a wide window.
Future<T?> showChoices<T>({required BuildContext context, required WidgetBuilder builder}) => isWide(context)
    ? showDialog<T>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .4),
        builder: (context) => Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: builder(context)),
        ),
      )
    : showCupertinoModalPopup<T>(context: context, builder: builder);

/// REST call to the configured server, through the tunnel; null if no server is set.
/// [body] is sent as JSON.
Future<String?> serverApi(String method, String path, {Map<String, String>? query, Object? body}) async {
  final base = Uri.tryParse(settings.url);
  if (base == null || !base.hasAuthority) {
    _reached(true); // no server to miss
    return null;
  }
  if (vpn.enabled) await vpn.ready;
  return _watch(
    callApi(
      base,
      method,
      path,
      query: query,
      body: body,
      user: settings.auth ? settings.user : null,
      password: settings.password,
    ).timeout(const Duration(seconds: 20)),
  );
}

/// False while the server can't be reached; every request tells, and [checkServer] asks again until it answers.
final online = ValueNotifier(true);
Timer? _again;
var _checking = false;

/// [call], noting in [online] whether it reached the server.
Future<T> _watch<T>(Future<T> call) async {
  try {
    final r = await call;
    _reached(true);
    return r;
  } catch (e) {
    if (unreachable(e)) {
      _reached(false);
    } else if (e is HttpException) {
      _reached(true); // the server answered, refusing
    }
    rethrow;
  }
}

void _reached(bool ok) {
  online.value = ok;
  if (ok) {
    _again?.cancel();
    _again = null;
  } else {
    _again ??= Timer.periodic(const Duration(seconds: 5), (_) => checkServer());
  }
}

/// Asks the server whether it is there, updating [online].
Future<void> checkServer() async {
  if (_checking) return;
  _checking = true;
  try {
    await serverApi('GET', '/api/status');
  } catch (_) {
    // [online] already tells
  } finally {
    _checking = false;
  }
}

/// Starts the tunnel afresh (when on) and reopens the chat connection, then asks the server again.
Future<void> reconnect() async {
  if (vpn.enabled) await vpn.apply();
  dropGateway();
  await checkServer();
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
  late final Future<Gateway?> opening;
  return _gateway = opening = () async {
    final base = Uri.tryParse(settings.url);
    if (base == null || !base.hasAuthority) return null;
    if (vpn.enabled) await vpn.ready;
    final g = await _watch(
      connectGateway(base, user: settings.auth ? settings.user : null, password: settings.password).timeout(const Duration(seconds: 20)),
    );
    g.events.listen(
      (e) {
        if (e.id == null && e.type.startsWith('subagent.')) trackSubagent(e.type, e.session, e.payload);
      },
      // lost rather than closed by [dropGateway]: is the server still there?
      onDone: () {
        if (identical(_gateway, opening)) checkServer();
      },
    );
    return g;
  }();
}

/// A child agent a chat handed work to (`delegate_task`); [session] is the chat's runtime session, [parent] the
/// subagent that started it ('' for the chat itself). [id] is the server's, '' from an older one (then it can't be steered).
typedef Subagent = ({
  String id,
  String parent,
  int depth,
  String goal,
  String session,
  String status,
  String tool,
  String summary,
  DateTime since,
  DateTime? ended,
});

/// The subagents of the chats on this connection, by id: they report on their chat's session, and an
/// asynchronous one keeps working after the reply that started it.
// ponytail: never pruned, the page shows the running and the recently ended ones; prune if a session lasts weeks
final subagents = ValueNotifier<Map<String, Subagent>>(const {});

bool subagentRunning(Subagent s) => s.ended == null;

/// [all] (by key) as a tree: each top-level one, running first, followed by those it started, with their depth.
List<(String, Subagent, int)> subagentTree(Map<String, Subagent> all) {
  final ids = {for (final a in all.values) a.id};
  final out = <(String, Subagent, int)>[];
  final seen = <String>{};
  void under(String parent, int depth) {
    final kids =
        [
          for (final MapEntry(:key, :value) in all.entries)
            if (parent.isEmpty ? value.parent.isEmpty || !ids.contains(value.parent) : value.parent == parent) (key, value),
        ]..sort(
          (a, b) => a.$2.ended == null && b.$2.ended != null
              ? -1
              : (b.$2.ended == null) != (a.$2.ended == null)
              ? 1
              : a.$2.since.compareTo(b.$2.since),
        );
    for (final (key, a) in kids) {
      if (!seen.add(key)) continue;
      out.add((key, a, depth));
      if (a.id.isNotEmpty) under(a.id, depth + 1);
    }
  }

  under('', 0);
  return out;
}

final _filed = <String>{}; // subagents already saved in a spawn tree

/// Once every subagent of [session] has ended, saves the run as a spawn tree (in the shape Hermes' terminal
/// UI writes), which the history lists later.
void _fileTree(String session) {
  final run = [
    for (final MapEntry(:key, :value) in subagents.value.entries)
      if (value.session == session && !_filed.contains(key)) (key, value),
  ];
  if (run.isEmpty || run.any((r) => subagentRunning(r.$2))) return;
  _filed.addAll(run.map((r) => r.$1));
  final start = run.map((r) => r.$2.since).reduce((a, b) => a.isBefore(b) ? a : b);
  () async {
    try {
      await (await gateway())?.call('spawn_tree.save', {
        'session_id': session,
        'label': [
          for (final (_, a) in run)
            if (a.parent.isEmpty) a.goal,
        ].join(' · '),
        'started_at': start.millisecondsSinceEpoch / 1000,
        'finished_at': DateTime.now().millisecondsSinceEpoch / 1000,
        'subagents': [
          for (final (i, (key, a)) in run.indexed)
            {
              'id': a.id.isEmpty ? key : a.id,
              'parentId': a.parent.isEmpty ? null : a.parent,
              'depth': a.depth,
              'index': i,
              'goal': a.goal,
              'status': a.status,
              'tools': [if (a.tool.isNotEmpty) a.tool],
              'summary': a.summary,
              'startedAt': a.since.millisecondsSinceEpoch,
              'durationSeconds': a.ended!.difference(a.since).inMilliseconds / 1000,
            },
        ],
      });
    } catch (e) {
      debugPrint('Spawn tree: $e');
    }
  }();
}

/// A node of a saved spawn tree, as a [Subagent].
Subagent subagentOfNode(Map n) {
  final since = DateTime.fromMillisecondsSinceEpoch(n['startedAt'] is num ? (n['startedAt'] as num).round() : 0);
  final tools = n['tools'] is List ? (n['tools'] as List) : const [];
  return (
    id: '${n['id'] ?? ''}',
    parent: '${n['parentId'] ?? ''}',
    depth: n['depth'] is int ? n['depth'] as int : 0,
    goal: '${n['goal'] ?? ''}'.trim(),
    session: '',
    status: '${n['status'] ?? 'completed'}',
    tool: tools.isEmpty ? '' : '${tools.last}',
    summary: '${n['summary'] ?? ''}'.trim(),
    since: since,
    ended: since.add(Duration(milliseconds: ((n['durationSeconds'] is num ? n['durationSeconds'] as num : 0) * 1000).round())),
  );
}

/// Folds a `subagent.*` event, or a `subagent.list` row (with no [type]), into [subagents].
void trackSubagent(String type, String session, Map p) {
  final id = '${p['subagent_id'] ?? '$session/${p['task_index']}/${p['goal']}'}';
  final was = subagents.value[id];
  if (was?.ended != null) return; // a late frame after the end
  final status = type == 'subagent.complete' ? '${p['status'] ?? 'completed'}' : '${p['status'] ?? 'running'}';
  final over = const {'completed', 'failed', 'error', 'timeout', 'interrupted'}.contains(status);
  subagents.value = {
    ...subagents.value,
    id: (
      id: '${p['subagent_id'] ?? ''}',
      parent: '${p['parent_id'] ?? was?.parent ?? ''}',
      depth: p['depth'] is int ? p['depth'] as int : was?.depth ?? 0,
      summary: '${p['summary'] ?? was?.summary ?? ''}'.trim(),
      goal: '${p['goal'] ?? was?.goal ?? ''}'.trim(),
      session: session,
      status: status,
      tool: '${p['tool_name'] ?? p['last_tool'] ?? was?.tool ?? ''}',
      since: switch (p['started_at']) {
        final num t => DateTime.fromMillisecondsSinceEpoch((t * 1000).round()),
        _ => was?.since ?? DateTime.now(),
      },
      ended: over ? DateTime.now() : null,
    ),
  };
  if (over) _fileTree(session);
}

/// Closes the chat connection and forgets the sign-in, e.g. after the server, sign-in or tunnel changed.
void dropGateway() {
  _gateway?.then((g) => g?.close(), onError: (Object _) {});
  _gateway = null;
  forgetSignIns();
}

/// User-facing text for a [serverOptions] failure; null [e] = no server set.
String serverErrorText(AppLocalizations l, Object? e) => switch (e) {
  null => l.serverNotSet,
  // Hermes updated on disk but not restarted: it refuses to list models
  HttpException(:final message) when message.startsWith('Restart required') => l.serverRestart,
  HttpException(:final message) => l.serverLoadFailed(message),
  _ => l.serverLoadFailed('$e'),
};

/// A strip above the app while the server doesn't answer, to try again (restarting the tunnel when on).
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({super.key, required this.child});
  final Widget child;

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  var trying = false;

  Future<void> retry() async {
    setState(() => trying = true);
    await reconnect();
    if (mounted) setState(() => trying = false);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: online,
    builder: (context, up, child) {
      if (up) return child!;
      final l = AppLocalizations.of(context);
      const white = TextStyle(fontSize: 14, color: Colors.white);
      return Column(
        children: [
          Material(
            color: CupertinoColors.systemOrange.darkColor,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.wifi_exclamationmark, size: 18, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(child: Text(vpn.enabled ? l.linkDownVpn : l.linkDown, style: white)),
                      trying
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CupertinoActivityIndicator(color: Colors.white),
                            )
                          : CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: const Size(0, 36),
                              onPressed: retry,
                              child: Text(vpn.enabled ? l.linkRestartVpn : l.linkRetry, style: white.copyWith(fontWeight: FontWeight.w600)),
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(context: context, removeTop: true, child: child!),
          ),
        ],
      );
    },
    child: widget.child,
  );
}

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
  bool canLock = false; // the device has an unlock to ask

  @override
  void initState() {
    super.initState();
    deviceAuth.available().then((v) => mounted ? setState(() => canLock = v) : null);
  }

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
          builder: (context, _) => readable(
            ListView(
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
                        child: Hover(
                          radius: 8,
                          child: CupertinoButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'OK',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                            ),
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
                      thumbColor: segmentThumb(c),
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
                            child: Text(l, style: TextStyle(fontSize: 15, color: segmentText(c, m == settings.theme))),
                          ),
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.accent, style: TextStyle(fontSize: 13, color: c.outline)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            for (final (i, v) in accents.indexed)
                              Hover(
                                radius: 999,
                                label: [
                                  l.accentNeutral,
                                  l.accentIndigo,
                                  l.accentBlue,
                                  l.accentTeal,
                                  l.accentGreen,
                                  l.accentOrange,
                                  l.accentPink,
                                  l.accentGold,
                                ][i],
                                child: GestureDetector(
                                  onTap: () => settings.accent = v,
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: settings.accent == v ? c.onSurface : Colors.transparent, width: 2),
                                    ),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: v == 0 ? null : Color(v),
                                        // neutral: the black and white it keeps
                                        gradient: v == 0
                                            ? const LinearGradient(
                                                colors: [Colors.black, Colors.black, Colors.white, Colors.white],
                                                stops: [0, .5, .5, 1],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              )
                                            : null,
                                        border: Border.all(color: c.outline.withValues(alpha: .4)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ]),
                section(l.language, [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    child: CupertinoSlidingSegmentedControl<String>(
                      groupValue: settings.language,
                      thumbColor: segmentThumb(c),
                      backgroundColor: c.surfaceContainerLow,
                      onValueChanged: (v) => settings.language = v!,
                      children: {
                        // each language named in itself, to be found whatever the current one
                        for (final (code, name) in [('', l.themeSystem), ('en', 'English'), ('fr', 'Français')])
                          code: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(name, style: TextStyle(fontSize: 15, color: segmentText(c, code == settings.language))),
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
                  CupertinoListTile(
                    title: Text(l.notifications, style: label),
                    subtitle: Text(l.notificationsInfo, maxLines: 2, style: TextStyle(fontSize: 13, color: c.outline)),
                    trailing: CupertinoSwitch(
                      value: settings.notifications,
                      onChanged: (v) {
                        settings.notifications = v;
                        if (v) const MethodChannel('herapp/quick').invokeMethod<void>('notifyAllow').catchError((Object _) {});
                      },
                    ),
                  ),
                  if (canLock)
                    CupertinoListTile(
                      title: Text(l.lockApp, style: label),
                      // turning it on proves the unlock works, so nobody is shut out
                      trailing: CupertinoSwitch(
                        value: settings.lock,
                        onChanged: (v) async {
                          if (!v || await confirmOwner(l.unlockReason)) settings.lock = v;
                        },
                      ),
                    ),
                  if (macCapable)
                    CupertinoListTile(
                      title: Text(l.macShell, style: label),
                      subtitle: Text(l.macShellHint, maxLines: 3, style: TextStyle(fontSize: 13, color: c.outline)),
                      trailing: CupertinoSwitch(value: settings.macShell, onChanged: (v) => settings.macShell = v),
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
                    Hover(
                      radius: 0,
                      child: CupertinoListTile(
                        title: Text(l.serverTest, style: label),
                        trailing: testing ? const CupertinoActivityIndicator() : null,
                        onTap: testing ? null : testServer,
                      ),
                    ),
                    // the server's health, updates and restarts: a page of the app, opened once settings close
                    Hover(
                      radius: 0,
                      child: CupertinoListTile(
                        leading: Icon(CupertinoIcons.desktopcomputer, size: 20, color: c.onSurfaceVariant),
                        title: Text(l.system, style: label),
                        trailing: const CupertinoListTileChevron(),
                        onTap: () => Navigator.pop(context, 'system'),
                      ),
                    ),
                  ],
                  footer: l.hermesServerFooter,
                  status: testResult,
                ),
                section(l.wireguard, [
                  Hover(
                    radius: 0,
                    child: CupertinoListTile(
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
                    Hover(
                      radius: 0,
                      child: CupertinoListTile(
                        title: Text(l.wgRemove, style: TextStyle(fontSize: 17, color: CupertinoColors.systemRed)),
                        onTap: vpn.remove,
                      ),
                    ),
                ], footer: importError ?? l.wgFooter),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
