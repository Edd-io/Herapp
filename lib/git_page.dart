import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cron_page.dart';
import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'mac.dart';
import 'settings.dart';

/// A git API call: the server's `/api/git/...` routes, or the same answered on this computer.
typedef GitApi = Future<Object?> Function(String method, String path, {Map<String, String>? query, Object? body});

Future<Object?> serverGit(String method, String path, {Map<String, String>? query, Object? body}) async =>
    jsonDecode(await serverApi(method, path, query: query, body: body) ?? (throw StateError('no server')));

/// Runs git (or gh) in [dir] through a login shell, for the PATH the user's profile sets.
Future<ProcessResult> _run(String dir, String tool, List<String> args) =>
    Process.run(MacShell.shell, ['-lc', '"\$@"', tool, tool, ...args], workingDirectory: dir);

Future<String> _out(String dir, String tool, List<String> args) async {
  final r = await _run(dir, tool, args);
  if (r.exitCode != 0) throw HttpException('${r.stderr}'.trim().isEmpty ? '$tool exited with ${r.exitCode}' : '${r.stderr}'.trim());
  return '${r.stdout}';
}

/// The server's git routes Herapp uses, answered with this computer's git, for a folder picked here.
Future<Object?> localGit(String method, String path, {Map<String, String>? query, Object? body}) async {
  final args = {...?query, ...?(body as Map?)?.cast<String, Object?>()};
  final dir = macPath('${args['path']}', home: MacShell.home, cwd: MacShell.home);
  switch (path) {
    case '/api/git/status':
      final r = await _run(dir, 'git', ['status', '--porcelain=v2', '--branch']);
      if (r.exitCode != 0) return null; // not a repository
      final lines = '${r.stdout}'.split('\n');
      String? head(String key) => lines.where((l) => l.startsWith('# $key ')).firstOrNull?.substring(key.length + 3);
      final ab = RegExp(r'\+(\d+) -(\d+)').firstMatch(head('branch.ab') ?? '');
      return {
        'branch': head('branch.head') == '(detached)' ? null : head('branch.head'),
        'ahead': int.tryParse(ab?[1] ?? '') ?? 0,
        'behind': int.tryParse(ab?[2] ?? '') ?? 0,
      };
    case '/api/git/review/list':
      final counts = <String, (int, int)>{};
      for (final l in (await _out(dir, 'git', ['diff', 'HEAD', '--numstat'])).split('\n')) {
        if (l.split('\t') case [final a, final r, final f]) counts[f] = (int.tryParse(a) ?? 0, int.tryParse(r) ?? 0);
      }
      return {
        'files': [
          for (final l in (await _out(dir, 'git', ['status', '--porcelain', '-uall'])).split('\n'))
            if (l.length > 3)
              {
                'path': l.substring(3).split(' -> ').last,
                'status': l.startsWith('??') ? '?' : l.substring(0, 2).trim().characters.first,
                'added': counts[l.substring(3).split(' -> ').last]?.$1 ?? 0,
                'removed': counts[l.substring(3).split(' -> ').last]?.$2 ?? 0,
              },
        ],
      };
    case '/api/git/review/diff':
      final file = '${args['file']}';
      final diff = await _out(dir, 'git', ['diff', 'HEAD', '--', file]);
      if (diff.isNotEmpty) return {'diff': diff};
      // untracked: all of it is new (exit 1 means it differs)
      return {
        'diff': '${(await _run(dir, 'git', ['diff', '--no-index', '--', '/dev/null', file])).stdout}',
      };
    case '/api/git/review/ship-info':
      final ready = (await _run(dir, 'gh', ['auth', 'status'])).exitCode == 0;
      final pr = ready ? await _run(dir, 'gh', ['pr', 'view', '--json', 'url,number,state']) : null;
      return {'ghReady': ready, 'pr': pr != null && pr.exitCode == 0 ? jsonDecode('${pr.stdout}') : null};
    case '/api/git/review/commit':
      await _out(dir, 'git', ['add', '-A']);
      await _out(dir, 'git', ['commit', '-m', '${args['message']}']);
      return {'ok': true};
    case '/api/git/review/push' || '/api/git/review/create-pr':
      final upstream = (await _run(dir, 'git', ['rev-parse', '--abbrev-ref', '@{u}'])).exitCode == 0;
      await _out(dir, 'git', upstream ? ['push'] : ['push', '-u', 'origin', 'HEAD']);
      if (path.endsWith('push')) return {'ok': true};
      return {
        'url': (await _out(dir, 'gh', ['pr', 'create', '--fill'])).trim().split('\n').last,
      };
  }
  throw UnsupportedError(path);
}

/// What the bot changed in a git repository on the server ([path]): the files, their diffs, then a
/// commit, a push or a pull request.
class GitPage extends StatefulWidget {
  const GitPage({super.key, required this.path, this.here = false});
  final String path; // empty: the server's default folder
  final bool here; // a folder of this computer

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

  late String path = widget.path;
  GitApi get api => widget.here ? localGit : serverGit;

  Future<void> load() async {
    try {
      if (path.isEmpty) path = '${((await serverGit('GET', '/api/fs/default-cwd')) as Map?)?['cwd'] ?? ''}';
      final q = {'path': path};
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
      final r = await api('POST', '/api/git/review/$action', body: {'path': path, if (action == 'commit') 'message': message.text.trim()});
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
                        path,
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
                                builder: (_) => _Diff(repo: path, file: '${f['path']}', api: api),
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
  const _Diff({required this.repo, required this.file, required this.api});
  final String repo, file;
  final GitApi api;

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
      final r = await widget.api('GET', '/api/git/review/diff', query: {'path': widget.repo, 'file': widget.file});
      text = '${(r as Map?)?['diff'] ?? ''}';
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
