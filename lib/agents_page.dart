import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'blueprint_text.dart';
import 'cron_page.dart';
import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'model_sheet.dart';
import 'quota_page.dart';
import 'settings.dart';
import 'subagent_page.dart';

/// Appended to a quiet agent's prompt: Hermes delivers nothing when a run answers `[SILENT]`.
const quietRule = '\n\nIf nothing is worth reporting, reply with exactly [SILENT].';

/// The agent's mission as the user wrote it, without [quietRule].
String missionOf(String prompt) => prompt.replaceAll(quietRule, '').trim();

/// How an agent is doing, which its [Critter] shows.
enum Mood { idle, working, asleep, trouble, done }

Mood moodOf(CronJob j) => switch (j) {
  _ when j.state == 'running' => Mood.working,
  _ when j.state == 'completed' => Mood.done,
  _ when !j.enabled => Mood.asleep,
  _ when j.lastError != null => Mood.trouble,
  _ => Mood.idle,
};

/// Agents are the scheduled jobs that think; the others only run a script.
List<CronJob> agentsOf(List<CronJob> jobs) => [
  for (final j in jobs)
    if (j.raw['no_agent'] != true) j,
];

String moodText(AppLocalizations l, CronJob j) => switch (moodOf(j)) {
  Mood.working => l.agentWorking,
  Mood.done => l.agentDone,
  Mood.asleep => l.agentAsleep,
  Mood.trouble => l.agentTrouble,
  Mood.idle when j.nextRun != null => l.agentWakesIn(durationText(l, j.nextRun!.difference(DateTime.now()))),
  Mood.idle => l.agentIdle,
};

/// The team page: every agent with its character and how it's doing.
class AgentsPage extends StatefulWidget {
  const AgentsPage({super.key});

  @override
  State<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<AgentsPage> {
  List<CronJob>? jobs;
  Board? board; // the kanban's workers, null without a kanban
  Object? error;
  final busy = <String>{}; // script ids with a request in flight
  late final Timer refresh = Timer.periodic(const Duration(seconds: 10), (_) => load()); // workers come and go

  @override
  void initState() {
    super.initState();
    load();
    refresh;
  }

  @override
  void dispose() {
    refresh.cancel();
    super.dispose();
  }

  /// Every board with cards; an older server only serves the active one.
  Future<Board?> loadBoard() async {
    final slugs = parseBoardSlugs(await serverApi('GET', '/api/plugins/kanban/boards').catchError((Object _) => null) ?? '');
    final bodies = await Future.wait([
      if (slugs.isEmpty) serverApi('GET', '/api/plugins/kanban/board'),
      for (final s in slugs) serverApi('GET', '/api/plugins/kanban/board', query: {'board': s}),
    ]);
    final boards = [for (final b in bodies) ?(b == null ? null : parseBoard(b))];
    return boards.isEmpty ? null : mergeBoards(boards);
  }

  Future<void> load() async {
    loadBoard()
        .then((b) {
          if (mounted) setState(() => board = b);
        })
        .catchError((Object e) {
          debugPrint('Kanban: $e'); // the kanban is a plugin: no board, no section
        });
    try {
      final body = await serverApi('GET', '/api/cron/jobs');
      if (!mounted) return;
      setState(() {
        jobs = body == null ? null : parseCronJobs(body);
        error = body == null ? 'no server' : null;
      });
    } catch (e) {
      debugPrint('Agents: $e');
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> open(CronJob j) async {
    await Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => AgentPage(id: j.id)));
    load();
  }

  /// Posts [action] (`pause`, `resume`, `trigger`) for a script, then refreshes.
  Future<void> act(CronJob j, String action) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy.add(j.id));
    try {
      await serverApi('POST', '/api/cron/jobs/${Uri.encodeComponent(j.id)}/$action');
      if (action == 'trigger') messenger.showSnackBar(SnackBar(content: Text(l.cronStarted(j.name))));
    } on TimeoutException {
      if (action == 'trigger') messenger.showSnackBar(SnackBar(content: Text(l.cronStarted(j.name)))); // a run outlasts the request
    } catch (e) {
      debugPrint('Script $action: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.cronActionFailed(e is HttpException ? e.message : '$e'))));
    }
    if (!mounted) return;
    await load();
    if (mounted) setState(() => busy.remove(j.id));
  }

  Future<void> edit(CronJob j) async {
    final changed = await Navigator.of(context).push<bool>(CupertinoPageRoute(builder: (_) => CronEditPage(job: j)));
    if (changed == true) load();
  }

  /// Picks a server blueprint (or a blank job) and creates the agent from it.
  Future<void> create() async {
    final made = await showPanel<bool>(context, (_) => const _NewAgentSheet(), scrollControlled: true);
    if (made == true) load();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final agents = jobs == null ? null : agentsOf(jobs!);
    final scripts = [...?jobs?.where((j) => !agents!.contains(j))];
    return PageFrame(
      title: l.agents,
      action: error == null
          ? IconButton(
              tooltip: l.agentNew,
              onPressed: create,
              icon: Icon(CupertinoIcons.add, color: c.onSurface),
            )
          : null,
      child: switch ((agents, error)) {
        (_, final Object e) => RefreshIndicator.adaptive(
          onRefresh: load,
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [_Note(serverErrorText(l, e is String ? null : e))]),
        ),
        (null, _) => const Center(child: CupertinoActivityIndicator()),
        (final List<CronJob> list, _) => RefreshIndicator.adaptive(
          onRefresh: load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 48),
            children: [
              if (list.isEmpty) ...[
                const SizedBox(height: 40),
                const Center(child: Critter('hermes', size: 96)),
                const SizedBox(height: 20),
                _Note(l.agentsEmpty, padding: 16),
                Center(
                  child: TextButton(
                    onPressed: create,
                    child: Text(l.agentNew, style: const TextStyle(fontSize: 17)),
                  ),
                ),
              ],
              for (final j in list)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), // the inset of the sections below
                  child: _AgentCard(j, onTap: () => open(j)),
                ),
              if (board case final b?) _Workers(b),
              ValueListenableBuilder(valueListenable: subagents, builder: (_, all, _) => _Subagents(all)),
              if (scripts.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  backgroundColor: c.surface,
                  decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                  separatorColor: c.outline.withValues(alpha: .2),
                  header: Text(l.agentScripts.toUpperCase(), style: TextStyle(fontSize: 13, color: c.outline)),
                  children: [
                    for (final j in scripts)
                      CronTile(
                        j,
                        busy: busy.contains(j.id),
                        onToggle: (on) => act(j, on ? 'resume' : 'pause'),
                        onRun: () => act(j, 'trigger'),
                        onTap: () => edit(j),
                      ),
                  ],
                ),
            ],
          ),
        ),
      },
    );
  }
}

/// The kanban's workers: the tasks running and the ones that keep failing, then the board's counts.
class _Workers extends StatelessWidget {
  const _Workers(this.board);
  final Board board;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    final now = DateTime.now();
    Widget row(KTask t, List<Widget> lines) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.onSurface),
          ),
          const SizedBox(height: 3),
          ...lines,
        ],
      ),
    );
    final counts = [
      for (final (status, text) in [
        ('ready', l.kanbanReady),
        ('todo', l.kanbanTodo),
        ('review', l.kanbanReview),
        ('blocked', l.kanbanBlocked),
        ('done', l.kanbanDone),
      ])
        if ((board.counts[status] ?? 0) > 0) text(board.counts[status]!),
    ];
    return CupertinoListSection.insetGrouped(
      backgroundColor: c.surface,
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      separatorColor: c.outline.withValues(alpha: .2),
      header: Text(l.workers.toUpperCase(), style: small),
      children: [
        for (final t in board.running)
          row(t, [
            Row(
              children: [
                Icon(CupertinoIcons.circle_fill, size: 8, color: CupertinoColors.systemGreen.resolveFrom(context)),
                const SizedBox(width: 6),
                Text(t.since == null ? l.workerRunning : l.workerSince(durationText(l, now.difference(t.since!))), style: small),
              ],
            ),
            // a worker silent for long has likely died without telling the board
            if (t.heartbeat case final hb? when now.difference(hb) > const Duration(minutes: 10))
              Text(
                l.workerSilent(durationText(l, now.difference(hb))),
                style: const TextStyle(fontSize: 13, color: CupertinoColors.systemOrange),
              ),
            if (t.summary.isNotEmpty) Text(t.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
          ]),
        if (board.running.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Text(l.workersNone, style: TextStyle(fontSize: 16, color: c.onSurface)),
          ),
        for (final t in board.failing)
          row(t, [
            Text(
              l.workerFailed(t.error),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: CupertinoColors.systemRed),
            ),
          ]),
        if (counts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text(counts.join(' · '), style: small),
          ),
      ],
    );
  }
}

/// The subagents the chats handed work to: the ones running, then those that ended in the last minutes.
/// One opens to steer or stop it.
class _Subagents extends StatelessWidget {
  const _Subagents(this.all);
  final Map<String, Subagent> all;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final shown = subagentTree({
      for (final MapEntry(:key, :value) in all.entries)
        if (value.ended == null || now.difference(value.ended!) < const Duration(minutes: 10)) key: value,
    });
    return CupertinoListSection.insetGrouped(
      backgroundColor: c.surface,
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      separatorColor: c.outline.withValues(alpha: .2),
      header: Text(l.subagents.toUpperCase(), style: TextStyle(fontSize: 13, color: c.outline)),
      children: [
        for (final (id, a, depth) in shown)
          SubagentRow(
            a,
            depth: depth,
            onTap: () => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => SubagentPage(id))),
          ),
        const _SubagentModel(),
        CupertinoListTile(
          title: Text(l.spawnTrees, style: TextStyle(fontSize: 16, color: c.onSurface)),
          leading: Icon(CupertinoIcons.tree, size: 20, color: c.onSurfaceVariant),
          trailing: const CupertinoListTileChevron(),
          onTap: () => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => const SpawnTreesPage())),
        ),
      ],
    );
  }
}

/// The model and effort subagents run with (`delegation.*` in the server's config); none = the chat's own.
class _SubagentModel extends StatefulWidget {
  const _SubagentModel();

  @override
  State<_SubagentModel> createState() => _SubagentModelState();
}

class _SubagentModelState extends State<_SubagentModel> {
  var model = '', effort = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      if (jsonDecode(await serverApi('GET', '/api/config') ?? '{}') case {'delegation': final Map d} when mounted) {
        final (p, m) = ('${d['provider'] ?? ''}'.trim(), '${d['model'] ?? ''}'.trim());
        setState(() {
          model = p.isEmpty || m.isEmpty ? m : '$p/$m';
          effort = '${d['reasoning_effort'] ?? ''}'.trim();
        });
      }
    } catch (e) {
      debugPrint('Subagent model: $e');
    }
  }

  /// Saves [changes] to the delegation block; the shown values go back to the server's on a failure.
  Future<void> save(Map<String, String> changes) async {
    final messenger = ScaffoldMessenger.of(context), l = AppLocalizations.of(context);
    try {
      await serverApi(
        'PUT',
        '/api/config',
        body: {
          'config': {'delegation': changes},
        },
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.toolsFailed(e is HttpException ? e.message : '$e'))));
      load();
    }
  }

  @override
  Widget build(BuildContext context) => ModelTile(
    model: model,
    effort: effort,
    none: AppLocalizations.of(context).subagentModelInherit,
    onModel: (id) {
      final slash = id.indexOf('/');
      setState(() => model = id);
      save({'provider': slash < 0 ? '' : id.substring(0, slash), 'model': slash < 0 ? id : modelName(id)});
    },
    onEffort: (e) {
      setState(() => effort = e);
      save({'reasoning_effort': e});
    },
  );
}

class _AgentCard extends StatelessWidget {
  const _AgentCard(this.job, {required this.onTap});
  final CronJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return Hover(
      radius: 18,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              Critter(job.id, mood: moodOf(job), size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.onSurface),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      moodText(l, job),
                      style: TextStyle(fontSize: 13, color: moodOf(job) == Mood.trouble ? CupertinoColors.systemRed : c.outline),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_forward, size: 18, color: c.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// One agent: its mission, rhythm, team and what it last said, with the everyday controls.
class AgentPage extends StatefulWidget {
  const AgentPage({super.key, required this.id});
  final String id;

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  List<CronJob> all = [];
  CronJob? job;
  String? said; // its latest reply; '' when it has none
  Object? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    load();
    loadSaid();
  }

  Future<void> load() async {
    try {
      final body = await serverApi('GET', '/api/cron/jobs');
      if (!mounted) return;
      all = body == null ? [] : parseCronJobs(body);
      setState(() => job = all.where((j) => j.id == widget.id).firstOrNull);
    } catch (e) {
      debugPrint('Agent: $e');
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> loadSaid() async {
    var text = '';
    try {
      final runs = parseCronRuns(await serverApi('GET', '/api/cron/jobs/${Uri.encodeComponent(widget.id)}/runs') ?? '');
      if (runs.firstOrNull case final r?) {
        text = r.session ? '' : runText(r, '\n\n'); // an agent run's preview is its prompt, not its words
        if (r.session) {
          final body = await serverApi('GET', '/api/sessions/${Uri.encodeComponent(r.id)}/messages');
          final reply = transcript((jsonDecode(body ?? '{}') as Map)['messages']).where((m) => !m.user).lastOrNull;
          if (reply != null && reply.text.trim().isNotEmpty) text = reply.text.trim();
        }
      }
    } catch (e) {
      debugPrint('Agent said: $e');
    }
    if (mounted) setState(() => said = text);
  }

  /// Runs a server call for this agent, shows its failure, then refreshes.
  Future<void> act(Future<void> Function() call, {String? done}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await call();
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    } on TimeoutException {
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done))); // a run outlasts the request
    } catch (e) {
      debugPrint('Agent action: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.cronActionFailed(e is HttpException ? e.message : '$e'))));
    }
    await load();
    if (mounted) setState(() => busy = false);
  }

  String get path => '/api/cron/jobs/${Uri.encodeComponent(widget.id)}';

  Future<void> update(Map<String, Object?> updates) => act(() => serverApi('PUT', path, body: {'updates': updates}));

  Future<void> pickTeam(CronJob j) async {
    final current = {...?(j.raw['context_from'] as List?)?.map((e) => '$e')};
    final others = agentsOf(all).where((a) => a.id != j.id).toList();
    final picked = await showPanel<Set<String>>(context, (_) => _TeamSheet(others: others, picked: current));
    if (picked == null || (picked.length == current.length && picked.containsAll(current))) return;
    await update({'context_from': picked.isEmpty ? null : picked.toList()});
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final j = job;
    if (j == null) {
      return PageFrame(
        title: '',
        child: error != null ? _Note(serverErrorText(l, error)) : const Center(child: CupertinoActivityIndicator()),
      );
    }
    final prompt = '${j.raw['prompt'] ?? ''}';
    final quiet = prompt.contains('[SILENT]');
    final team = [for (final id in (j.raw['context_from'] as List?) ?? const []) ?all.where((a) => a.id == '$id').firstOrNull];
    final small = TextStyle(fontSize: 13, color: c.outline);
    final body = TextStyle(fontSize: 16, color: c.onSurface);
    Widget section(List<Widget> children, {String? header}) => CupertinoListSection.insetGrouped(
      backgroundColor: c.surface,
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      separatorColor: c.outline.withValues(alpha: .2),
      header: header == null ? null : Text(header.toUpperCase(), style: small),
      children: children,
    );
    Widget switchRow(String label, bool value, ValueChanged<bool>? onChanged) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: body)),
          CupertinoSwitch(value: value, onChanged: busy ? null : onChanged),
        ],
      ),
    );
    final completed = j.state == 'completed';

    return PageFrame(
      title: '',
      action: busy ? const Padding(padding: EdgeInsets.all(14), child: CupertinoActivityIndicator()) : null,
      child: RefreshIndicator.adaptive(
        onRefresh: () => Future.wait([load(), loadSaid()]),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 48),
          children: [
            Center(child: Critter(j.id, mood: moodOf(j), size: 120)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                j.name,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.onSurface),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              moodText(l, j),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: moodOf(j) == Mood.trouble ? CupertinoColors.systemRed : c.outline),
            ),
            if (j.lastError case final e?)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 6, 32, 0),
                child: Text(e, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: small),
              ),
            const SizedBox(height: 16),
            Center(
              child: FilledButton.icon(
                onPressed: busy ? null : () => act(() => serverApi('POST', '$path/trigger'), done: l.cronStarted(j.name)),
                icon: const Icon(CupertinoIcons.bolt_fill, size: 18),
                label: Text(l.agentWake),
              ),
            ),
            section(header: l.agentSaid, [
              Padding(
                padding: const EdgeInsets.all(16),
                child: switch (said) {
                  null => const Center(child: CupertinoActivityIndicator()),
                  '' => Text(l.agentSaidNothing, style: TextStyle(fontSize: 15, color: c.outline)),
                  final s => SelectableText(s, maxLines: 12, style: body.copyWith(height: 1.4)),
                },
              ),
              Hover(
                radius: 0,
                child: CupertinoListTile(
                  title: Text(l.cronRuns, style: body),
                  trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: c.outline),
                  onTap: () => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => CronRunsPage(job: j))),
                ),
              ),
            ]),
            section(header: l.agentMission, [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(missionOf(prompt).isEmpty ? '—' : missionOf(prompt), style: body.copyWith(height: 1.4)),
              ),
              if (j.schedule.isNotEmpty)
                CupertinoListTile(
                  title: Text(l.agentRhythm, style: body),
                  additionalInfo: Text(j.schedule, style: small),
                ),
              ModelTile(
                model: jobModel(j.raw),
                effort: '${j.raw['reasoning_effort'] ?? ''}',
                onModel: (id) => update(jobModelUpdates(id)),
                onEffort: (e) => update({'reasoning_effort': e}),
              ),
            ]),
            section([
              switchRow(
                l.agentActive,
                j.enabled && !completed,
                completed ? null : (on) => act(() => serverApi('POST', '$path/${on ? 'resume' : 'pause'}')),
              ),
              // a [SILENT] rule written by hand (or by a blueprint) can't be switched off from here
              switchRow(
                l.agentQuiet,
                quiet,
                quiet && !prompt.contains(quietRule.trim())
                    ? null
                    : (on) => update({'prompt': on ? missionOf(prompt) + quietRule : missionOf(prompt)}),
              ),
            ]),
            section(header: l.agentTeam, [
              Hover(
                radius: 0,
                child: CupertinoListTile(
                  title: team.isEmpty
                      ? Text(l.agentTeamNone, style: TextStyle(fontSize: 16, color: c.outline))
                      : Row(
                          children: [
                            for (final a in team)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Tooltip(
                                  message: a.name,
                                  child: Critter(a.id, mood: moodOf(a), size: 34),
                                ),
                              ),
                          ],
                        ),
                  trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: c.outline),
                  onTap: busy ? null : () => pickTeam(j),
                ),
              ),
            ]),
            section([
              Hover(
                radius: 0,
                child: CupertinoListTile(
                  title: Text(l.agentSettings, style: body),
                  trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: c.outline),
                  onTap: () async {
                    final nav = Navigator.of(context);
                    final changed = await nav.push<bool>(CupertinoPageRoute(builder: (_) => CronEditPage(job: j)));
                    if (changed != true) return;
                    await load();
                    if (mounted && job == null) nav.pop(); // deleted
                  },
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Which other agents' latest output this one reads before working.
class _TeamSheet extends StatefulWidget {
  const _TeamSheet({required this.others, required this.picked});
  final List<CronJob> others;
  final Set<String> picked;

  @override
  State<_TeamSheet> createState() => _TeamSheetState();
}

class _TeamSheetState extends State<_TeamSheet> {
  late final picked = {...widget.picked};

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.agentTeam,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(context, picked), child: Text(l.cronSave)),
            ],
          ),
        ),
        if (widget.others.isEmpty) _Note(l.agentTeamAlone, padding: 24),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final a in widget.others)
                ListTile(
                  leading: Critter(a.id, mood: moodOf(a), size: 40),
                  title: Text(
                    a.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.onSurface),
                  ),
                  trailing: Icon(
                    picked.contains(a.id) ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                    color: picked.contains(a.id) ? c.primary : c.outline,
                  ),
                  onTap: () => setState(() => picked.contains(a.id) ? picked.remove(a.id) : picked.add(a.id)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// New agent: the server's blueprints (morning briefing, mail watch…) or a blank job.
class _NewAgentSheet extends StatefulWidget {
  const _NewAgentSheet();

  @override
  State<_NewAgentSheet> createState() => _NewAgentSheetState();
}

class _NewAgentSheetState extends State<_NewAgentSheet> {
  List<Map>? blueprints;

  @override
  void initState() {
    super.initState();
    serverApi('GET', '/api/cron/blueprints')
        .then((body) {
          final j = body == null ? null : jsonDecode(body);
          if (mounted) setState(() => blueprints = [if (j case {'blueprints': final List b}) ...b.whereType<Map>()]);
        })
        .catchError((Object e) {
          debugPrint('Blueprints: $e');
          if (mounted) setState(() => blueprints = []);
        });
  }

  Future<void> start(Widget page) async {
    final made = await Navigator.of(context).push<bool>(CupertinoPageRoute(builder: (_) => page));
    if (made == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    Widget row(String seed, String title, String subtitle, VoidCallback onTap) => ListTile(
      leading: Critter(seed, size: 44),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, color: c.onSurface),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.outline),
            ),
      onTap: onTap,
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            l.agentNew,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
          ),
        ),
        row('blank', l.agentBlank, l.agentBlankHint, () => start(const CronEditPage())),
        if (blueprints == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CupertinoActivityIndicator()),
          )
        else
          for (final b in blueprints!)
            row(
              '${b['key']}',
              blueprintText(context, '${b['title'] ?? b['key']}'),
              blueprintText(context, '${b['description'] ?? ''}'),
              () => start(BlueprintPage(blueprint: b)),
            ),
      ],
    );
  }
}

/// Fills a blueprint's slots (time, choice, text) and creates the agent; pops true once made.
class BlueprintPage extends StatefulWidget {
  const BlueprintPage({super.key, required this.blueprint});
  final Map blueprint;

  @override
  State<BlueprintPage> createState() => _BlueprintPageState();
}

class _BlueprintPageState extends State<BlueprintPage> {
  late final fields = [...((widget.blueprint['fields'] as List?) ?? const []).whereType<Map>()];
  late final values = {for (final f in fields) '${f['name']}': f['default'] == null ? '' : '${f['default']}'};
  late final text = {
    for (final f in fields)
      // the server's example text, in the app's language (it's the user's words from here on)
      if (f['type'] == 'text') '${f['name']}': TextEditingController(text: blueprintText(context, values['${f['name']}']!)),
  };
  String model = '', effort = ''; // the server's default
  bool saving = false;

  @override
  void dispose() {
    for (final t in text.values) {
      t.dispose();
    }
    super.dispose();
  }

  List<String> options(Map f) => switch (f['options']) {
    final List o when o.isNotEmpty => [for (final x in o) '$x'],
    _ when f['type'] == 'weekdays' => weekdayPresets,
    _ => const [],
  };

  Future<void> pick(Map f) async {
    final name = '${f['name']}';
    final l = AppLocalizations.of(context);
    String? v;
    if (f['type'] == 'time') {
      final parts = values[name]!.split(':');
      var picked = DateTime(2000, 1, 1, int.tryParse(parts.first) ?? 8, parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
      final ok = await showChoices<bool>(
        context: context,
        builder: (context) => Container(
          height: 300,
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l.ok)),
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: true,
                    initialDateTime: picked,
                    onDateTimeChanged: (d) => picked = d,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (ok == true) v = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    } else {
      v = await showChoices<String>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: Text(blueprintText(context, '${f['label'] ?? name}')),
          actions: [
            for (final o in options(f))
              CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, o), child: Text(blueprintText(context, o))),
          ],
          cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        ),
      );
    }
    if (v != null) setState(() => values[name] = v!);
  }

  Future<void> save() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    for (final MapEntry(:key, :value) in text.entries) {
      values[key] = value.text.trim();
    }
    final language = agentLanguage(context);
    setState(() => saving = true);
    try {
      final made = await serverApi(
        'POST',
        '/api/cron/blueprints/instantiate',
        body: {
          'blueprint': widget.blueprint['key'],
          'values': {...values}..removeWhere((_, v) => v.isEmpty),
        },
      );
      final job = switch (jsonDecode(made ?? '{}')) {
        {'job': final Map j} => j,
        final Map j => j,
        _ => const {},
      };
      final updates = {
        // the blueprint's prompt is English: ask for the app's language
        if ((language, job['prompt']) case (final String language, final String p)) 'prompt': '$p\n\nWrite your messages in $language.',
        if (model.isNotEmpty) ...jobModelUpdates(model),
        if (effort.isNotEmpty) 'reasoning_effort': effort,
      };
      if (job['id'] case final String id when updates.isNotEmpty) {
        await serverApi('PUT', '/api/cron/jobs/${Uri.encodeComponent(id)}', body: {'updates': updates});
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Blueprint: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.cronActionFailed(e is HttpException ? e.message : '$e'))));
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    final b = widget.blueprint;
    return PageFrame(
      title: blueprintText(context, '${b['title'] ?? ''}'),
      action: saving
          ? const Padding(padding: EdgeInsets.all(14), child: CupertinoActivityIndicator())
          : TextButton(
              onPressed: save,
              child: Text(l.agentCreate, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          Center(child: Critter('${b['key']}', size: 96)),
          if ('${b['description'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
              child: Text(
                blueprintText(context, '${b['description']}'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: c.onSurfaceVariant),
              ),
            ),
          CupertinoListSection.insetGrouped(
            backgroundColor: c.surface,
            decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
            separatorColor: c.outline.withValues(alpha: .2),
            children: [
              for (final f in fields)
                if (f['type'] == 'text')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(blueprintText(context, '${f['label'] ?? f['name']}'), style: small),
                        const SizedBox(height: 4),
                        TextField(
                          controller: text['${f['name']}'],
                          minLines: 1,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(fontSize: 16, color: c.onSurface),
                          decoration: InputDecoration.collapsed(
                            hintText: blueprintText(context, '${f['help'] ?? ''}'),
                            hintStyle: TextStyle(fontSize: 16, color: c.outline.withValues(alpha: .6)),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Hover(
                    radius: 0,
                    child: CupertinoListTile(
                      title: Text(blueprintText(context, '${f['label'] ?? f['name']}'), style: TextStyle(fontSize: 16, color: c.onSurface)),
                      subtitle: '${f['help'] ?? ''}'.isEmpty
                          ? null
                          : Text(blueprintText(context, '${f['help']}'), maxLines: 2, style: small),
                      additionalInfo: Text(
                        values['${f['name']}']!.isEmpty ? '—' : blueprintText(context, values['${f['name']}']!),
                        style: small,
                      ),
                      trailing: Icon(CupertinoIcons.chevron_up_chevron_down, size: 16, color: c.outline),
                      onTap: () => pick(f),
                    ),
                  ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            backgroundColor: c.surface,
            decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
            children: [
              ModelTile(
                model: model,
                effort: effort,
                onModel: (id) => setState(() => model = id),
                onEffort: (e) => setState(() => effort = e),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.padding = 32});
  final String text;
  final double padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(padding),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.outline),
    ),
  );
}

/// An agent's little character: shape, color and accessory come from [seed], the face from [mood].
/// It breathes and blinks, bounces while working and snoozes when paused (still if animations are off).
class Critter extends StatefulWidget {
  const Critter(this.seed, {super.key, this.mood = Mood.idle, this.size = 56});
  final String seed;
  final Mood mood;
  final double size;

  @override
  State<Critter> createState() => _CritterState();
}

class _CritterState extends State<Critter> with SingleTickerProviderStateMixin {
  late final clock = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      clock.stop();
    } else if (!clock.isAnimating) {
      clock.repeat();
    }
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _CritterPainter(_hash(widget.seed), widget.mood, clock, Theme.of(context).brightness == Brightness.dark),
    ),
  );
}

/// FNV-1a: the same seed draws the same character on every launch (String.hashCode may not).
int _hash(String s) {
  var h = 0x811c9dc5;
  for (final u in s.codeUnits) {
    h = ((h ^ u) * 0x01000193) & 0xffffffff;
  }
  return h;
}

class _CritterPainter extends CustomPainter {
  _CritterPainter(this.seed, this.mood, this.clock, this.dark) : super(repaint: clock);
  final int seed;
  final Mood mood;
  final Animation<double> clock;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width, v = clock.value, tau = 2 * math.pi;
    final r = math.Random(seed);
    final hue = r.nextDouble() * 360, square = r.nextBool(), extra = r.nextInt(4), gap = .17 + r.nextDouble() * .05;
    final dull = mood == Mood.asleep || mood == Mood.trouble;
    final skin = HSLColor.fromAHSL(1, hue, dull ? .22 : .62, dark ? .6 : .66).toColor();
    final ink = Paint()
      ..color = const Color(0xFF221C2B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .035
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = skin;

    final working = mood == Mood.working;
    final breath = math.sin(v * tau * (working ? 4 : 1));
    final w = s * .76 * (1 + .025 * breath), h = s * .64 * (1 - .025 * breath);
    final center = Offset(s / 2, s * .58 - (working ? breath.abs() * s * .05 : 0));
    final body = Rect.fromCenter(center: center, width: w, height: h);
    final top = body.top;

    // accessory, behind the body
    switch (extra) {
      case 1: // antenna
        final tip = Offset(center.dx + math.sin(v * tau * 2) * s * .04, top - s * .15);
        canvas.drawLine(Offset(center.dx, top + s * .02), tip, ink..strokeWidth = s * .03);
        canvas.drawCircle(tip, s * .05, Paint()..color = HSLColor.fromAHSL(1, (hue + 40) % 360, .7, .6).toColor());
      case 2: // ears
        for (final dx in [-.28, .28]) {
          canvas.drawCircle(Offset(center.dx + w * dx, top + s * .05), s * .11, fill);
        }
      case 3: // sprout
        canvas.drawLine(Offset(center.dx, top + s * .02), Offset(center.dx, top - s * .08), ink..strokeWidth = s * .03);
        final leaf = Paint()..color = const Color(0xFF5BBF6A);
        for (final a in [-.6, .6]) {
          canvas.save();
          canvas.translate(center.dx, top - s * .08);
          canvas.rotate(a + math.sin(v * tau) * .1);
          canvas.drawOval(Rect.fromCenter(center: Offset(a.sign * s * .06, 0), width: s * .13, height: s * .07), leaf);
          canvas.restore();
        }
    }
    ink.strokeWidth = s * .035;

    if (square) {
      canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(w * .32)), fill);
    } else {
      canvas.drawOval(body, fill);
    }

    // cheeks
    final cheek = Paint()..color = const Color(0xFFFF7A9A).withValues(alpha: mood == Mood.trouble ? .15 : .35);
    for (final dx in [-1, 1]) {
      canvas.drawCircle(Offset(center.dx + dx * w * (gap + .13), center.dy + h * .12), s * .055, cheek);
    }

    // eyes
    final eyeY = center.dy - h * .06;
    final look = working ? math.sin(v * tau * 2) * s * .03 : math.sin(v * tau) * s * .012;
    final blink = v < .035 || (v > .5 && v < .53 && seed.isEven);
    for (final dx in [-1, 1]) {
      final eye = Offset(center.dx + dx * w * gap, eyeY);
      switch (mood) {
        case Mood.asleep:
          canvas.drawArc(Rect.fromCenter(center: eye, width: s * .14, height: s * .09), 0, math.pi, false, ink);
        case Mood.done:
          canvas.drawArc(Rect.fromCenter(center: eye.translate(0, s * .02), width: s * .14, height: s * .12), math.pi, math.pi, false, ink);
        case _ when blink:
          canvas.drawLine(eye.translate(-s * .06, 0), eye.translate(s * .06, 0), ink);
        case _:
          canvas.drawOval(Rect.fromCenter(center: eye, width: s * .16, height: s * .18), Paint()..color = Colors.white);
          canvas.drawCircle(eye.translate(look, s * .01), s * .05, Paint()..color = const Color(0xFF221C2B));
          canvas.drawCircle(eye.translate(look + s * .02, -s * .015), s * .016, Paint()..color = Colors.white);
      }
      if (mood == Mood.trouble) {
        // worried brows
        canvas.drawLine(eye.translate(-dx * s * .07, -s * .1), eye.translate(dx * s * .05, -s * .14), ink);
      }
    }

    // mouth
    final mouth = Offset(center.dx, center.dy + h * .2);
    switch (mood) {
      case Mood.working:
        canvas.drawOval(
          Rect.fromCenter(center: mouth, width: s * .07, height: s * (.05 + .03 * breath.abs())),
          Paint()..color = const Color(0xFF221C2B),
        );
      case Mood.trouble:
        canvas.drawArc(Rect.fromCenter(center: mouth.translate(0, s * .03), width: s * .14, height: s * .08), math.pi, math.pi, false, ink);
      case Mood.asleep:
        canvas.drawLine(mouth.translate(-s * .03, 0), mouth.translate(s * .03, 0), ink);
      case Mood.done:
        canvas.drawArc(Rect.fromCenter(center: mouth.translate(0, -s * .02), width: s * .2, height: s * .14), 0, math.pi, false, ink);
      case Mood.idle:
        canvas.drawArc(Rect.fromCenter(center: mouth.translate(0, -s * .02), width: s * .14, height: s * .09), 0, math.pi, false, ink);
    }

    // a snooze or a busy halo
    if (mood == Mood.asleep) {
      final z = TextPainter(
        text: TextSpan(
          text: 'z',
          style: TextStyle(
            fontSize: s * .2,
            fontWeight: FontWeight.w700,
            color: (dark ? Colors.white : const Color(0xFF221C2B)).withValues(alpha: 1 - v),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      z.paint(canvas, Offset(s * .74 + v * s * .08, s * .22 - v * s * .2));
    } else if (working) {
      final dot = Paint()..color = HSLColor.fromAHSL(1, (hue + 40) % 360, .8, .62).toColor();
      for (var i = 0; i < 3; i++) {
        final a = v * tau + i * tau / 3;
        canvas.drawCircle(center + Offset(math.cos(a) * s * .48, math.sin(a) * s * .4), s * .03, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_CritterPainter old) => old.seed != seed || old.mood != mood || old.dark != dark;
}
