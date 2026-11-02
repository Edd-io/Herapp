import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'cron_page.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';

/// The Hermes server itself: its version and health, its updates, a restart of its gateway.
class SystemPage extends StatefulWidget {
  const SystemPage({super.key});

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> {
  Map? status, update, stats; // `/api/status`, `/api/hermes/update/check`, `/api/system/stats`
  Object? error;
  bool updating = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<Map> call(String method, String path, [Map<String, String>? query]) async =>
      switch (jsonDecode(await serverApi(method, path, query: query) ?? (throw StateError('no server')))) {
        final Map m => m,
        _ => throw const FormatException('not an object'),
      };

  /// Reads the server's state; [force] asks the update source again instead of its 24 h answer.
  Future<void> load({bool force = false}) async {
    try {
      final s = await call('GET', '/api/status');
      if (!mounted) return;
      setState(() {
        status = s;
        error = null;
      });
    } catch (e) {
      debugPrint('System: $e');
      if (mounted) setState(() => error = e);
      return;
    }
    try {
      final m = await call('GET', '/api/system/stats');
      if (mounted) setState(() => stats = m);
    } catch (e) {
      debugPrint('Stats: $e');
    }
    try {
      final u = await call('GET', '/api/hermes/update/check', {if (force) 'force': 'true'});
      if (mounted) setState(() => update = u);
    } catch (e) {
      debugPrint('Update check: $e'); // the rest still shows
    }
  }

  /// Asks before an action that stops the replies in progress.
  Future<bool> confirm(String action, String message) async =>
      await showChoices<bool>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          message: Text(message),
          actions: [
            CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
        ),
      ) ==
      true;

  void say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  String reason(Object e) => e is HttpException ? e.message : '$e';

  Future<void> restart() async {
    final l = AppLocalizations.of(context);
    if (!await confirm(l.systemRestart, l.systemRestartConfirm)) return;
    try {
      await call('POST', '/api/gateway/restart');
      say(l.systemRestarting);
    } catch (e) {
      say(l.systemFailed(reason(e)));
    }
  }

  /// Runs `hermes update` on the server and follows it to the end.
  Future<void> install() async {
    final l = AppLocalizations.of(context);
    if (!await confirm(l.systemUpdateNow, l.systemUpdateConfirm)) return;
    setState(() => updating = true);
    String? outcome;
    try {
      final r = await call('POST', '/api/hermes/update');
      if (r['ok'] == false) throw HttpException('${r['message'] ?? r['error']}'); // e.g. a Docker install
      // ponytail: polls every 2 s for up to 10 min; the server restarts on the way, so failed reads just wait
      for (var i = 0; i < 300 && outcome == null; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final Map a;
        try {
          a = await call('GET', '/api/actions/hermes-update/status');
        } catch (_) {
          continue;
        }
        if (a['running'] == true) continue;
        final code = a['exit_code'];
        outcome = code is int && code != 0
            ? l.systemFailed(
                [for (final x in a['lines'] as List? ?? const []) '$x'].lastWhere((x) => x.trim().isNotEmpty, orElse: () => 'exit $code'),
              )
            : l.systemUpdated;
      }
    } catch (e) {
      outcome = l.systemFailed(reason(e));
    }
    if (!mounted) return;
    setState(() => updating = false);
    if (outcome != null) say(outcome);
    load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    const good = Color(0xFF34C759), bad = Color(0xFFFF9500);
    Widget section(String title, List<Widget> children, {String? footer}) => CupertinoListSection.insetGrouped(
      backgroundColor: c.surface,
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      separatorColor: c.outline.withValues(alpha: .2),
      header: Text(title.toUpperCase(), style: small),
      footer: footer == null ? null : Text(footer, style: small),
      children: children,
    );
    Widget row(String title, String value, {Color? dot}) => CupertinoListTile(
      title: Text(title, style: TextStyle(fontSize: 16, color: c.onSurface)),
      additionalInfo: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(value, style: TextStyle(fontSize: 15, color: c.outline)),
        ],
      ),
    );
    Widget action(String title, VoidCallback? onTap, {Color? color}) => Hover(
      radius: 0,
      child: CupertinoListTile(
        title: Text(title, style: TextStyle(fontSize: 16, color: color ?? c.primary)),
        trailing: onTap == null ? const CupertinoActivityIndicator() : null,
        onTap: onTap,
      ),
    );

    final s = status, u = update, m = stats;
    final number = NumberFormat.decimalPattern('${Localizations.localeOf(context)}')..maximumFractionDigits = 1;
    Color level(num percent) => percent >= 90
        ? const Color(0xFFD93025)
        : percent >= 75
        ? bad
        : good;
    // memory or disk: used of total, in GB
    Widget space(String title, Object? v) => switch (v) {
      {'total': final num total, 'used': final num used, 'percent': final num percent} => row(
        title,
        l.systemSpace(number.format(used / 1e9), number.format(total / 1e9), percent.round()),
        dot: level(percent),
      ),
      _ => const SizedBox.shrink(),
    };
    final platforms = s?['components'] is Map ? (s!['components'] as Map)['platforms'] : null;
    final gatewayState = '${s?['gateway_state'] ?? (s?['gateway_running'] == true ? 'running' : 'stopped')}';
    final released = DateTime.tryParse('${s?['release_date']}');
    final behind = u?['behind'] is int ? u!['behind'] as int : null;
    return PageFrame(
      title: l.system,
      child: s == null
          ? error == null
                ? const Center(child: CupertinoActivityIndicator())
                : Padding(
                    padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
                    child: Text(
                      serverErrorText(l, error is StateError ? null : error),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: c.outline),
                    ),
                  )
          : RefreshIndicator.adaptive(
              onRefresh: () => load(force: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 48),
                children: [
                  section(l.systemServer, [
                    row(
                      l.systemVersion,
                      [
                        '${s['version'] ?? ''}',
                        if (released != null) DateFormat.yMMMd('${Localizations.localeOf(context)}').format(released),
                      ].where((x) => x.isNotEmpty).join(' · '),
                    ),
                    row(l.systemGateway, switch (gatewayState) {
                      'running' => l.systemRunning,
                      'stopped' => l.systemStopped,
                      final other => other,
                    }, dot: gatewayState == 'running' ? good : bad),
                    if (s['overall'] case final String overall)
                      row(l.systemHealth, overall == 'ok' ? l.systemHealthy : l.systemDegraded, dot: overall == 'ok' ? good : bad),
                    if (platforms case {'configured': final int total, 'connected': final int n} when total > 0)
                      row(l.systemPlatforms, l.systemConnected(n, total), dot: n == total ? good : bad),
                    if (s['active_sessions'] case final int n) row(l.systemSessions, '$n'),
                  ]),
                  if (m != null)
                    section(l.systemMachine, [
                      if (m['cpu_percent'] case final num cpu)
                        row(
                          l.systemCpu,
                          [
                            '${cpu.round()} %',
                            if (m['load_avg'] case [final num one, ...]) l.systemLoad(number.format(one), '${m['cpu_count'] ?? '?'}'),
                          ].join(' · '),
                          dot: level(cpu),
                        ),
                      space(l.systemMemory, m['memory']),
                      space(l.systemDisk, m['disk']),
                      if (m['uptime_seconds'] case final int up) row(l.systemUptime, l.systemUptimeValue(up ~/ 86400, up % 86400 ~/ 3600)),
                    ]),
                  if (u != null)
                    section(
                      l.systemUpdate,
                      [
                        if (u['update_available'] == true) ...[
                          row(l.systemUpdateReady, behind != null && behind > 0 ? l.systemChanges(behind) : ''),
                          for (final commit in (u['commits'] as List? ?? const []).whereType<Map>().take(5))
                            CupertinoListTile(
                              title: Text('${commit['summary'] ?? ''}', maxLines: 2, style: TextStyle(fontSize: 14, color: c.onSurface)),
                            ),
                          if (u['can_apply'] == true) action(updating ? l.systemUpdating : l.systemUpdateNow, updating ? null : install),
                        ] else
                          row(behind == 0 ? l.systemUpToDate : '${u['message'] ?? ''}', ''),
                      ],
                      // why it can't update itself (Docker, a managed install…) and the command that does
                      footer: u['update_available'] == true && u['can_apply'] != true
                          ? [u['message'], u['update_command']].where((x) => x is String && x.isNotEmpty).join('\n')
                          : null,
                    ),
                  section(l.systemGateway, [action(l.systemRestart, restart, color: const Color(0xFFD93025))]),
                ],
              ),
            ),
    );
  }
}
