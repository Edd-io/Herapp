import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cron_page.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';

const _account = {'type': 'account'}; // the connectors of the whole account, not of one chat

/// Calls a `connectors.*` method on the chat connection.
Future<Map> _call(String method, [Map<String, Object?> params = const {}]) async {
  final g = await gateway();
  if (g == null) throw StateError('no server');
  return g.call(method, params, const Duration(seconds: 45)); // connecting waits for the portal up to ~31 s
}

/// Asks for [change] to the account's connector policy, against its current revision.
Future<void> _setPolicy(Map<String, Object?> change) async {
  final p = await _call('connectors.policy.get');
  final member = (p['layers'] as List? ?? const []).whereType<Map>().where((l) => l['kind'] == 'member').firstOrNull;
  final revision = member?['revision'] ?? (p['effective'] as Map?)?['revision'];
  await _call('connectors.policy.set', {'change': change, 'expected_revision': revision});
}

String _failure(AppLocalizations l, Object e) => e is HttpException ? e.message : serverErrorText(l, e is StateError ? null : e);

/// The services the bot reaches through Hermes' hosted connectors (Gmail, calendars…): those connected, each
/// switched on or off for the bot, and the catalog to connect more, through the service's own sign-in page.
class ConnectorsPage extends StatefulWidget {
  const ConnectorsPage({super.key});

  @override
  State<ConnectorsPage> createState() => _ConnectorsPageState();
}

class _ConnectorsPageState extends State<ConnectorsPage> with WidgetsBindingObserver {
  List<Map>? catalog, states, accounts; // `connectors.catalog`, `.list`, `.accounts`
  bool available = true;
  Object? error;
  final busy = <String>{}; // connector slugs being switched or connected
  final search = TextEditingController();
  String? waiting; // the operation a sign-in page is open for

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    super.dispose();
  }

  // back from the browser: the server may already know the sign-in went through
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && waiting != null) {
      _call('connectors.operation.wake', {'owner': _account, 'op_id': waiting}).ignore();
    }
  }

  Future<void> load() async {
    try {
      final [c, s, a] = await Future.wait([
        _call('connectors.catalog'),
        _call('connectors.list', {'owner': _account}),
        _call('connectors.accounts'),
      ]);
      if (!mounted) return;
      setState(() {
        catalog = [...(c['connectors'] as List? ?? const []).whereType<Map>()];
        available = s['available'] != false;
        states = [...(s['connectors'] as List? ?? const []).whereType<Map>()];
        accounts = [...(a['accounts'] as List? ?? const []).whereType<Map>()];
        error = null;
      });
    } catch (e) {
      debugPrint('Connectors: $e');
      if (mounted) setState(() => error = e);
    }
  }

  Map? stateOf(String slug) => states?.where((s) => s['connector'] == slug).firstOrNull;
  Map? infoOf(String slug) => catalog?.where((c) => c['slug'] == slug).firstOrNull;

  void tell(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Opens [slug]'s sign-in page, then follows the server's operation until it settles.
  Future<void> connect(String slug) async {
    final l = AppLocalizations.of(context);
    setState(() => busy.add(slug));
    try {
      var op = await _call('connectors.connect', {
        'owner': _account,
        'connectors': [slug],
      });
      final url = (op['targets'] as List? ?? const []).whereType<Map>().map((t) => t['connect_url']).whereType<String>().firstOrNull;
      if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      waiting = '${op['op_id']}';
      // ponytail: polls every 2 s up to the server's 10 min deadline; the `connection.update` events could replace it
      final until = DateTime.now().add(const Duration(minutes: 10));
      while (mounted && op['settled'] != true && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        op = await _call('connectors.operation.status', {'owner': _account, 'op_id': waiting});
      }
      final state = (op['targets'] as List? ?? const []).whereType<Map>().firstOrNull?['state'];
      if (mounted) tell(state == 'connected' ? l.connectorConnected('${infoOf(slug)?['name'] ?? slug}') : l.connectorNotConnected);
    } catch (e) {
      if (mounted) tell(l.chatActionFailed(_failure(l, e)));
    }
    waiting = null;
    if (!mounted) return;
    setState(() => busy.remove(slug));
    load();
  }

  /// Lets the bot use [slug], or not.
  Future<void> enable(String slug, bool on) async {
    final l = AppLocalizations.of(context);
    settings.haptic();
    setState(() => busy.add(slug));
    try {
      await _setPolicy({'type': 'connector', 'connector': slug, 'enabled': on});
      stateOf(slug)?['enabled'] = on;
    } catch (e) {
      tell(l.chatActionFailed(_failure(l, e)));
    }
    if (mounted) setState(() => busy.remove(slug));
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
    Widget logo(String slug) => switch (infoOf(slug)?['logo_url']) {
      final String url when url.startsWith('http') => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          url,
          width: 28,
          height: 28,
          errorBuilder: (_, _, _) => Icon(CupertinoIcons.link, size: 22, color: c.onSurfaceVariant),
        ),
      ),
      _ => Icon(CupertinoIcons.link, size: 22, color: c.onSurfaceVariant),
    };

    final connected = {
      for (final s in states ?? const <Map>[])
        if (s['connected'] == true) '${s['connector']}',
    };
    final query = search.text.trim().toLowerCase();
    final more = [
      for (final k in catalog ?? const <Map>[])
        if (!connected.contains(k['slug']) &&
            (query.isEmpty || '${k['name']} ${k['description'] ?? ''} ${k['category'] ?? ''}'.toLowerCase().contains(query)))
          k,
    ];
    final categories = {for (final k in more) '${k['category'] ?? ''}'}.toList()..sort((a, b) => a.isEmpty ? 1 : a.compareTo(b));

    return PageFrame(
      title: l.connectors,
      child: switch ((catalog, error)) {
        (null, null) => const Center(child: CupertinoActivityIndicator()),
        (null, final e) => Padding(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
          child: Text(
            _failure(l, e!),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: c.outline),
          ),
        ),
        _ when !available => Padding(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
          child: Text(
            l.connectorsUnavailable,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: c.outline),
          ),
        ),
        _ => RefreshIndicator.adaptive(
          onRefresh: load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 48),
            children: [
              if (connected.isNotEmpty)
                section(l.connectorsConnected, [
                  for (final slug in connected)
                    CupertinoListTile(
                      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                      leading: logo(slug),
                      title: Text('${infoOf(slug)?['name'] ?? slug}', style: TextStyle(fontSize: 16, color: c.onSurface)),
                      subtitle: Text(
                        [
                          for (final a in accounts ?? const <Map>[])
                            if (a['connector'] == slug) '${a['alias'] ?? a['label'] ?? ''}',
                        ].where((t) => t.isNotEmpty).join(', '),
                        maxLines: 1,
                        style: small,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CupertinoSwitch(
                            value: stateOf(slug)?['enabled'] != false,
                            onChanged: busy.contains(slug) ? null : (v) => enable(slug, v),
                          ),
                          const CupertinoListTileChevron(),
                        ],
                      ),
                      onTap: () => Navigator.of(context)
                          .push(
                            CupertinoPageRoute<void>(
                              builder: (_) => _Connector(slug, '${infoOf(slug)?['name'] ?? slug}', onReconnect: () => connect(slug)),
                            ),
                          )
                          .then((_) => load()),
                    ),
                ], footer: l.connectorsFooter),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: CupertinoSearchTextField(controller: search, placeholder: l.toolsSearch, onChanged: (_) => setState(() {})),
              ),
              for (final cat in categories)
                section(cat.isEmpty ? l.connectorsMore : cat, [
                  for (final k in more.where((k) => '${k['category'] ?? ''}' == cat))
                    CupertinoListTile(
                      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                      leading: logo('${k['slug']}'),
                      title: Text('${k['name'] ?? k['slug']}', style: TextStyle(fontSize: 16, color: c.onSurface)),
                      subtitle: '${k['description'] ?? ''}'.isEmpty
                          ? null
                          : Text('${k['description']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
                      trailing: busy.contains(k['slug'])
                          ? const CupertinoActivityIndicator()
                          : CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              onPressed: () => connect('${k['slug']}'),
                              child: Text(l.connectorConnect, style: const TextStyle(fontSize: 15)),
                            ),
                    ),
                ]),
            ],
          ),
        ),
      },
    );
  }
}

/// A connected service: its accounts (each disconnected on its own) and the actions the bot may take with it.
class _Connector extends StatefulWidget {
  const _Connector(this.slug, this.name, {required this.onReconnect});
  final String slug, name;
  final VoidCallback onReconnect;

  @override
  State<_Connector> createState() => _ConnectorState();
}

class _ConnectorState extends State<_Connector> {
  List<Map>? accounts, tools;
  Set<String> off = {}; // the tools the policy turns off
  final busy = <String>{};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final [a, t, p] = await Future.wait([
        _call('connectors.accounts', {'connector': widget.slug}),
        _call('connectors.tools', {'slug': widget.slug}),
        _call('connectors.policy.get'),
      ]);
      if (!mounted) return;
      setState(() {
        accounts = [...(a['accounts'] as List? ?? const []).whereType<Map>()];
        tools = [...(t['tools'] as List? ?? const []).whereType<Map>().where((t) => t['deprecated'] != true)];
        off = {...(((p['effective'] as Map?)?['tools'] as Map?)?[widget.slug] as List? ?? const []).map((s) => '$s')};
      });
    } catch (e) {
      debugPrint('Connector: $e');
      if (mounted) setState(() => accounts ??= const []);
    }
  }

  Future<void> run(String key, Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy.add(key));
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.chatActionFailed(_failure(l, e)))));
    }
    if (mounted) setState(() => busy.remove(key));
  }

  Future<void> allow(String tool, bool on) => run(tool, () async {
    final next = on ? (off..remove(tool)) : (off..add(tool));
    await _setPolicy({'type': 'tools', 'connector': widget.slug, 'disabled_tools': next.toList()});
  });

  Future<void> remove(Map a) => run('${a['connection_id']}', () async {
    await _call('connectors.accounts.remove', {'connection_id': a['connection_id']});
    accounts!.remove(a);
    if (accounts!.isEmpty && mounted) Navigator.of(context).pop();
  });

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
    return PageFrame(
      title: widget.name,
      child: accounts == null
          ? const Center(child: CupertinoActivityIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 48),
              children: [
                section(l.connectorAccounts, [
                  for (final a in accounts!)
                    CupertinoListTile(
                      title: Text('${a['alias'] ?? a['label'] ?? a['connection_id']}', style: TextStyle(fontSize: 16, color: c.onSurface)),
                      subtitle: Text('${a['status'] ?? ''}', style: small),
                      trailing: busy.contains('${a['connection_id']}')
                          ? const CupertinoActivityIndicator()
                          : CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              onPressed: () => remove(a),
                              child: Text(l.connectorRemove, style: const TextStyle(fontSize: 15, color: CupertinoColors.systemRed)),
                            ),
                    ),
                  CupertinoListTile(
                    title: Text(l.connectorReconnect, style: TextStyle(fontSize: 16, color: c.primary)),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onReconnect();
                    },
                  ),
                ]),
                if (tools case final tools? when tools.isNotEmpty)
                  section(l.connectorActions, [
                    for (final t in tools)
                      CupertinoListTile(
                        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${t['name'] ?? t['slug']}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 16, color: c.onSurface),
                              ),
                            ),
                            if (t['facet'] case 'write' || 'destructive') ...[
                              const SizedBox(width: 6),
                              Icon(
                                t['facet'] == 'write' ? CupertinoIcons.pencil : CupertinoIcons.exclamationmark_triangle,
                                size: 14,
                                color: t['facet'] == 'write' ? c.outline : CupertinoColors.systemOrange,
                              ),
                            ],
                          ],
                        ),
                        subtitle: '${t['description'] ?? ''}'.isEmpty
                            ? null
                            : Text('${t['description']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
                        trailing: CupertinoSwitch(
                          value: !off.contains(t['slug']),
                          onChanged: busy.contains('${t['slug']}') ? null : (v) => allow('${t['slug']}', v),
                        ),
                      ),
                  ], footer: l.connectorActionsFooter),
              ],
            ),
    );
  }
}
