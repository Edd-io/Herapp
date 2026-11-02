import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cron_page.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';

/// What the bot changed in a git repository on the server ([path]): the files, their diffs, then a
/// commit, a push or a pull request.
class GitPage extends StatefulWidget {
  const GitPage({super.key, required this.path});
  final String path;

  @override
  State<GitPage> createState() => _GitPageState();
}

class _GitPageState extends State<GitPage> {
  Map? status, ship; // `/api/git/status`, `/api/git/review/ship-info`
  List<Map>? files; // `/api/git/review/list`
  Object? error;
  var loaded = false;
  String? doing; // the action under way
  final message = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<Object?> api(String method, String path, {Map<String, String>? query, Object? body}) async =>
      jsonDecode(await serverApi(method, path, query: query, body: body) ?? (throw StateError('no server')));

  Future<void> load() async {
    try {
      final q = {'path': widget.path};
      final [s, list, shipped] = await Future.wait([
        api('GET', '/api/git/status', query: q),
        api('GET', '/api/git/review/list', query: q),
        api('GET', '/api/git/review/ship-info', query: q).catchError((Object _) => null), // no gh: no PR
      ]);
      if (!mounted) return;
      setState(() {
        status = s as Map?;
        files = [...((list as Map?)?['files'] as List? ?? const []).whereType<Map>()];
        ship = shipped as Map?;
        error = null;
        loaded = true;
      });
    } catch (e) {
      debugPrint('Git: $e');
      if (mounted) setState(() => error = e);
    }
  }

  /// Runs [action] (`commit`, `push`, `create-pr`) and refreshes; a pull request opens once made.
  Future<void> act(String action) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    settings.haptic();
    setState(() => doing = action);
    try {
      final r = await api(
        'POST',
        '/api/git/review/$action',
        body: {'path': widget.path, if (action == 'commit') 'message': message.text.trim()},
      );
      if (action == 'commit') message.clear();
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (action) {
            'commit' => l.gitCommitted,
            'push' => l.gitPushed,
            _ => l.gitPrOpened,
          }),
        ),
      );
      if (r case {'url': final String url}) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).ignore();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.gitFailed(e is HttpException ? e.message : '$e'))));
    }
    if (!mounted) return;
    await load();
    if (mounted) setState(() => doing = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    const added = Color(0xFF34C759), removed = Color(0xFFFF453A);
    Widget section(String title, List<Widget> children, {String? footer}) => CupertinoListSection.insetGrouped(
      backgroundColor: c.surface,
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      separatorColor: c.outline.withValues(alpha: .2),
      header: Text(title.toUpperCase(), style: small),
      footer: footer == null ? null : Text(footer, style: small),
      children: children,
    );
    Widget action(String title, String name, {bool enabled = true}) => Hover(
      radius: 0,
      child: CupertinoListTile(
        title: Text(title, style: TextStyle(fontSize: 16, color: enabled ? c.primary : c.outline)),
        trailing: doing == name ? const CupertinoActivityIndicator() : null,
        onTap: doing != null || !enabled ? null : () => act(name),
      ),
    );

    final s = status, list = files ?? const <Map>[], pr = ship?['pr'];
    final ahead = s?['ahead'] is int ? s!['ahead'] as int : 0;
    return PageFrame(
      title: l.gitTitle,
      child: !loaded
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: Text(
                      [
                        widget.path,
                        if (s?['branch'] case final String b) b,
                        if (ahead > 0) l.gitAhead(ahead),
                        if (s?['behind'] case final int n when n > 0) l.gitBehind(n),
                      ].join(' · '),
                      textAlign: TextAlign.center,
                      style: small,
                    ),
                  ),
                  if (s == null)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l.gitNotRepo,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: c.outline),
                      ),
                    )
                  else ...[
                    section(l.gitChanges, [
                      if (list.isEmpty)
                        CupertinoListTile(
                          title: Text(l.gitClean, style: TextStyle(fontSize: 16, color: c.outline)),
                        ),
                      for (final f in list)
                        Hover(
                          radius: 0,
                          child: CupertinoListTile(
                            title: Text(
                              '${f['path']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, color: c.onSurface),
                            ),
                            leading: Text(
                              '${f['status'] ?? ''}',
                              style: TextStyle(fontFamily: 'Menlo', fontSize: 13, fontWeight: FontWeight.w600, color: c.outline),
                            ),
                            additionalInfo: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '+${f['added'] ?? 0} ',
                                    style: const TextStyle(color: added),
                                  ),
                                  TextSpan(
                                    text: '−${f['removed'] ?? 0}',
                                    style: const TextStyle(color: removed),
                                  ),
                                ],
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Icon(CupertinoIcons.chevron_forward, size: 16, color: c.outline),
                            onTap: () => Navigator.of(context).push(
                              CupertinoPageRoute<void>(
                                builder: (_) => _Diff(repo: widget.path, file: '${f['path']}'),
                              ),
                            ),
                          ),
                        ),
                    ]),
                    if (list.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: CupertinoTextField(
                          controller: message,
                          placeholder: l.gitMessage,
                          minLines: 1,
                          maxLines: 4,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      section('', [action(l.gitCommit, 'commit', enabled: message.text.trim().isNotEmpty)]),
                    ],
                    section(l.gitShare, [
                      action(ahead > 0 ? l.gitPushCount(ahead) : l.gitPush, 'push', enabled: ahead > 0),
                      if (pr case {'url': final String url, 'number': final Object n})
                        Hover(
                          radius: 0,
                          child: CupertinoListTile(
                            title: Text(l.gitPrSee('$n'), style: TextStyle(fontSize: 16, color: c.primary)),
                            trailing: Icon(CupertinoIcons.arrow_up_right, size: 16, color: c.outline),
                            onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                          ),
                        )
                      else if (ship?['ghReady'] == true)
                        action(l.gitPr, 'create-pr'),
                    ]),
                  ],
                ],
              ),
            ),
    );
  }
}

/// One file's changes, as a diff colored line by line.
class _Diff extends StatefulWidget {
  const _Diff({required this.repo, required this.file});
  final String repo, file;

  @override
  State<_Diff> createState() => _DiffState();
}

class _DiffState extends State<_Diff> {
  String? diff;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    var text = '';
    try {
      final body = await serverApi('GET', '/api/git/review/diff', query: {'path': widget.repo, 'file': widget.file});
      text = '${(jsonDecode(body ?? '{}') as Map)['diff'] ?? ''}';
    } catch (e) {
      text = e is HttpException ? e.message : '$e';
    }
    if (mounted) setState(() => diff = text);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final lines = diff?.split('\n') ?? const <String>[];
    return PageFrame(
      title: widget.file.split('/').last,
      full: true,
      child: diff == null
          ? const Center(child: CupertinoActivityIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 48),
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  TextSpan(
                    children: [
                      for (final line in lines)
                        TextSpan(
                          text: '$line\n',
                          style: TextStyle(
                            color: line.startsWith('@@')
                                ? c.primary
                                : line.startsWith('+') && !line.startsWith('+++')
                                ? const Color(0xFF34C759)
                                : line.startsWith('-') && !line.startsWith('---')
                                ? const Color(0xFFFF453A)
                                : c.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  style: const TextStyle(fontFamily: 'Menlo', fontFamilyFallback: ['monospace'], fontSize: 12.5, height: 1.4),
                ),
              ),
            ),
    );
  }
}
