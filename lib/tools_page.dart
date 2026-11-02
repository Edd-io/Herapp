import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'cron_page.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';

/// What the bot can use: its MCP servers and its skills, each switched on or off (for the next chats).
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  List<Map>? servers, skills; // `/api/mcp/servers`, `/api/skills`
  Object? error;
  final busy = <String>{}, tested = <String, String>{}; // by 'mcp:name' / 'skill:name'; a server's test outcome
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<Object?> api(String method, String path, [Object? body]) async =>
      jsonDecode(await serverApi(method, path, body: body) ?? (throw StateError('no server')));

  Future<void> load() async {
    try {
      final [m, s] = await Future.wait([api('GET', '/api/mcp/servers'), api('GET', '/api/skills')]);
      if (!mounted) return;
      setState(() {
        servers = [...((m as Map?)?['servers'] as List? ?? const []).whereType<Map>()];
        skills = [...(s as List? ?? const []).whereType<Map>()];
        error = null;
      });
    } catch (e) {
      debugPrint('Tools: $e');
      if (mounted) setState(() => error = e);
    }
  }

  /// Switches [item] (an MCP server or a skill) to [on].
  Future<void> toggle(String kind, Map item, bool on) async {
    final key = '$kind:${item['name']}';
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    settings.haptic();
    setState(() => busy.add(key));
    try {
      await (kind == 'mcp'
          ? api('PUT', '/api/mcp/servers/${Uri.encodeComponent('${item['name']}')}/enabled', {'enabled': on})
          : api('PUT', '/api/skills/toggle', {'name': item['name'], 'enabled': on}));
      item['enabled'] = on;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.toolsFailed(e is HttpException ? e.message : '$e'))));
    }
    if (mounted) setState(() => busy.remove(key));
  }

  /// Connects to the server [s] and tells how many tools it offers, or why it fails.
  Future<void> test(Map s) async {
    final key = 'mcp:${s['name']}';
    final l = AppLocalizations.of(context);
    setState(() => busy.add(key));
    String outcome;
    try {
      final r = await api('POST', '/api/mcp/servers/${Uri.encodeComponent('${s['name']}')}/test') as Map;
      outcome = r['ok'] == true ? l.toolsMcpOk((r['tools'] as List? ?? const []).length) : '${r['error'] ?? l.toolsMcpFailed}';
    } catch (e) {
      outcome = e is HttpException ? e.message : '$e';
    }
    if (mounted) {
      setState(() {
        busy.remove(key);
        tested['${s['name']}'] = outcome;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    Widget section(String title, List<Widget> children, {String? footer}) => CupertinoListSection.insetGrouped(
      backgroundColor: c.surface,
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      separatorColor: c.outline.withValues(alpha: .2),
      header: Text(title.toUpperCase(), style: small),
      footer: footer == null ? null : Text(footer, style: small),
      children: children,
    );
    Widget tile(String kind, Map item, String subtitle, {Widget? extra}) => CupertinoListTile(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      title: Text('${item['name']}', style: TextStyle(fontSize: 16, color: c.onSurface)),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?extra,
          CupertinoSwitch(
            value: item['enabled'] == true,
            // a plugin's server is the plugin's to switch
            onChanged: busy.contains('$kind:${item['name']}') || item['source'] == 'plugin' ? null : (v) => toggle(kind, item, v),
          ),
        ],
      ),
    );

    final query = search.text.trim().toLowerCase();
    final shown = [
      for (final s in skills ?? const <Map>[])
        if (query.isEmpty || '${s['name']} ${s['description'] ?? ''} ${s['category'] ?? ''}'.toLowerCase().contains(query)) s,
    ];
    final categories = {for (final s in shown) '${s['category'] ?? ''}'}.toList()..sort((a, b) => a.isEmpty ? 1 : a.compareTo(b));

    return PageFrame(
      title: l.tools,
      child: servers == null || skills == null
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
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 48),
                children: [
                  if (servers!.isNotEmpty)
                    section(l.toolsMcp, [
                      for (final s in servers!)
                        tile(
                          'mcp',
                          s,
                          tested['${s['name']}'] ?? '${s['url'] ?? [s['command'], ...?(s['args'] as List?)].whereType<String>().join(' ')}',
                          extra: busy.contains('mcp:${s['name']}')
                              ? const Padding(padding: EdgeInsets.only(right: 8), child: CupertinoActivityIndicator(radius: 8))
                              : IconButton(
                                  tooltip: l.toolsMcpTest,
                                  onPressed: () => test(s),
                                  icon: Icon(CupertinoIcons.bolt_horizontal, size: 18, color: c.onSurfaceVariant),
                                ),
                        ),
                    ], footer: l.toolsNextChats),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: CupertinoSearchTextField(controller: search, placeholder: l.toolsSearch, onChanged: (_) => setState(() {})),
                  ),
                  for (final cat in categories)
                    section(cat.isEmpty ? l.toolsSkills : cat, [
                      for (final s in shown.where((s) => '${s['category'] ?? ''}' == cat)) tile('skill', s, '${s['description'] ?? ''}'),
                    ]),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(l.toolsNone, textAlign: TextAlign.center, style: small),
                    ),
                ],
              ),
            ),
    );
  }
}
