import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'cron_page.dart';
import 'l10n/app_localizations.dart';
import 'quota_page.dart';
import 'settings.dart';

/// A subagent's goal over its state: running for how long with which tool, or how it ended.
class SubagentRow extends StatelessWidget {
  const SubagentRow(this.a, {super.key, this.depth = 0, this.onTap});
  final Subagent a;
  final int depth; // under the subagent that started it
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    final row = Padding(
      padding: EdgeInsets.fromLTRB(16 + depth * 18.0, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (depth > 0) ...[
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(CupertinoIcons.arrow_turn_down_right, size: 13, color: c.outline),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.goal,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.onSurface),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    switch (a) {
                      _ when subagentRunning(a) => Icon(
                        CupertinoIcons.circle_fill,
                        size: 8,
                        color: CupertinoColors.systemGreen.resolveFrom(context),
                      ),
                      _ when a.status == 'completed' => Icon(CupertinoIcons.checkmark, size: 13, color: c.outline),
                      _ => const Icon(CupertinoIcons.xmark, size: 13, color: CupertinoColors.systemRed),
                    },
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        switch (a) {
                          _ when subagentRunning(a) => [
                            l.workerSince(durationText(l, DateTime.now().difference(a.since))),
                            if (a.tool.isNotEmpty) a.tool,
                          ].join(' · '),
                          _ when a.status == 'completed' => l.subagentDone,
                          _ => l.subagentFailed,
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onTap != null) ...[const SizedBox(width: 8), Icon(CupertinoIcons.chevron_forward, size: 16, color: c.outline)],
        ],
      ),
    );
    return onTap == null
        ? row
        : Hover(
            radius: 0,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row),
          );
  }
}

/// A subagent close up: what it is doing (its transcript's end), a word to steer it, and stopping it.
class SubagentPage extends StatefulWidget {
  const SubagentPage(this.id, {super.key});
  final String id; // its key in [subagents]

  @override
  State<SubagentPage> createState() => _SubagentPageState();
}

class _SubagentPageState extends State<SubagentPage> {
  final say = TextEditingController();
  String tail = '';
  bool sending = false, stopping = false;
  Timer? again;

  Subagent? get a => subagents.value[widget.id];

  @override
  void initState() {
    super.initState();
    load();
    again = Timer.periodic(const Duration(seconds: 2), (_) {
      if (a case final a? when subagentRunning(a)) load();
    });
  }

  @override
  void dispose() {
    again?.cancel();
    say.dispose();
    super.dispose();
  }

  /// Calls [method] on the subagent, through the chat connection that runs its chat.
  Future<Map> call(String method, [Map<String, Object?> more = const {}]) async {
    final a = this.a!;
    final g = await gateway();
    if (g == null) throw const HttpException('no server');
    return g.call(method, {'session_id': a.session, 'subagent_id': a.id, ...more});
  }

  Future<void> load() async {
    if (a?.id.isEmpty ?? true) return;
    try {
      final r = await call('subagent.tail');
      if (mounted && r['available'] == true) setState(() => tail = '${r['text'] ?? ''}'.trim());
    } catch (e) {
      debugPrint('Subagent: $e');
    }
  }

  Future<void> steer() async {
    final text = say.text.trim();
    if (text.isEmpty) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => sending = true);
    try {
      final r = await call('subagent.steer', {'text': text});
      say.clear();
      messenger.showSnackBar(SnackBar(content: Text(r['status'] == 'queued' ? l.subagentSteered : l.subagentSteerRefused)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.chatActionFailed(e is HttpException ? e.message : '$e'))));
    }
    if (mounted) setState(() => sending = false);
  }

  Future<void> stop() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => stopping = true);
    try {
      await call('subagent.interrupt');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.chatActionFailed(e is HttpException ? e.message : '$e'))));
    }
    if (mounted) setState(() => stopping = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: subagents,
      builder: (context, all, _) {
        final a = all[widget.id];
        if (a == null) return PageFrame(title: l.subagents, child: const SizedBox.shrink());
        final live = subagentRunning(a) && a.id.isNotEmpty;
        return PageFrame(
          title: l.subagents,
          action: live
              ? stopping
                    ? const Padding(padding: EdgeInsets.all(12), child: CupertinoActivityIndicator())
                    : CupertinoButton(
                        onPressed: stop,
                        child: Text(l.macStop, style: const TextStyle(color: CupertinoColors.systemRed)),
                      )
              : null,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    SubagentRow(a),
                    if (a.summary.isNotEmpty || tail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                          child: SelectableText(
                            a.summary.isNotEmpty && !subagentRunning(a) ? a.summary : tail,
                            style: TextStyle(fontFamily: 'Menlo', fontSize: 12.5, height: 1.4, color: c.onSurface),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (live)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: CupertinoTextField(
                            controller: say,
                            placeholder: l.subagentSteerHint,
                            onSubmitted: (_) => steer(),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            style: TextStyle(color: c.onSurface),
                            decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        sending
                            ? const CupertinoActivityIndicator()
                            : Hover(
                                radius: 999,
                                label: l.a11ySend,
                                child: GestureDetector(
                                  onTap: steer,
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                                    child: Icon(CupertinoIcons.arrow_up, size: 18, color: c.onPrimary),
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The delegation runs saved on the server, newest first; one opens as its tree.
class SpawnTreesPage extends StatefulWidget {
  const SpawnTreesPage({super.key});

  @override
  State<SpawnTreesPage> createState() => _SpawnTreesPageState();
}

class _SpawnTreesPageState extends State<SpawnTreesPage> {
  List<Map>? entries;
  Object? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final g = await gateway();
      if (g == null) throw StateError('no server');
      final r = await g.call('spawn_tree.list', {'cross_session': true, 'limit': 50});
      if (mounted) setState(() => entries = [...(r['entries'] as List? ?? const []).whereType<Map>()]);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final locale = '${Localizations.localeOf(context)}';
    Widget note(String text) => Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: c.outline),
      ),
    );
    return PageFrame(
      title: l.spawnTrees,
      child: switch (entries) {
        null when error != null => note(serverErrorText(l, error is StateError ? null : error)),
        null => const Center(child: CupertinoActivityIndicator()),
        [] => note(l.spawnTreesNone),
        final entries => ListView(
          children: [
            for (final e in entries)
              CupertinoListTile(
                title: Text('${e['label'] ?? ''}', maxLines: 1, style: TextStyle(fontSize: 16, color: c.onSurface)),
                subtitle: Text(
                  [
                    if (e['finished_at'] case final num at)
                      DateFormat.MMMd(locale).add_Hm().format(DateTime.fromMillisecondsSinceEpoch((at * 1000).round())),
                    l.spawnTreeCount(e['count'] is int ? e['count'] as int : 0),
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: c.outline),
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: () =>
                    Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => _SpawnTree('${e['path']}', '${e['label'] ?? ''}'))),
              ),
          ],
        ),
      },
    );
  }
}

/// A saved delegation run: who started whom, and how each ended.
class _SpawnTree extends StatefulWidget {
  const _SpawnTree(this.path, this.label);
  final String path, label;

  @override
  State<_SpawnTree> createState() => _SpawnTreeState();
}

class _SpawnTreeState extends State<_SpawnTree> {
  Map<String, Subagent>? nodes;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await (await gateway())!.call('spawn_tree.load', {'path': widget.path});
      final all = (r['subagents'] as List? ?? const []).whereType<Map>().map(subagentOfNode);
      if (mounted) setState(() => nodes = {for (final (i, a) in all.indexed) a.id.isEmpty ? '$i' : a.id: a});
    } catch (e) {
      debugPrint('Spawn tree: $e');
      if (mounted) setState(() => nodes = const {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return PageFrame(
      title: widget.label,
      child: nodes == null
          ? const Center(child: CupertinoActivityIndicator())
          : ListView(
              children: [
                for (final (_, a, depth) in subagentTree(nodes!)) ...[
                  SubagentRow(a, depth: depth),
                  if (a.summary.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16 + depth * 18.0 + (depth > 0 ? 19 : 0), 0, 16, 12),
                      child: Text(
                        a.summary,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.onSurfaceVariant),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
