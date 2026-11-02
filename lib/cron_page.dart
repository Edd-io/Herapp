import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'model_sheet.dart';
import 'quota_page.dart';
import 'settings.dart';

/// A script-only job's row: its schedule and state, with run now and a pause switch.
class CronTile extends StatelessWidget {
  const CronTile(this.job, {super.key, required this.busy, required this.onToggle, required this.onRun, required this.onTap});
  final CronJob job;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRun;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    final now = DateTime.now();
    final completed = job.state == 'completed';
    return Hover(
      radius: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.name,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.onSurface),
                    ),
                    if (job.schedule.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(job.schedule, style: small),
                      ),
                    const SizedBox(height: 4),
                    if (job.state == 'running')
                      Text(l.cronRunning, style: small)
                    else if (job.enabled && !completed && job.nextRun != null)
                      Text(l.cronNext(durationText(l, job.nextRun!.difference(now))), style: small)
                    else if (completed)
                      Text(l.cronCompleted, style: small),
                    if (job.lastError != null)
                      Text(
                        l.cronLastFailed(job.lastError!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: CupertinoColors.systemRed),
                      )
                    else if (job.lastRun != null)
                      Text(l.cronLast(durationText(l, now.difference(job.lastRun!))), style: small),
                  ],
                ),
              ),
              if (busy)
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: CupertinoActivityIndicator())
              else
                IconButton(
                  tooltip: l.cronRunNow,
                  onPressed: onRun,
                  icon: Icon(CupertinoIcons.play_fill, size: 20, color: c.onSurface),
                ),
              CupertinoSwitch(value: job.enabled && !completed, onChanged: busy || completed ? null : onToggle),
            ],
          ),
        ),
      ),
    );
  }
}

/// Creates ([job] null) or edits a scheduled job, every field the server takes; pops true once saved or deleted.
class CronEditPage extends StatefulWidget {
  const CronEditPage({super.key, this.job});
  final CronJob? job;

  @override
  State<CronEditPage> createState() => _CronEditPageState();
}

class _CronEditPageState extends State<CronEditPage> {
  late final Map raw = widget.job?.raw ?? const {};
  late final initial = cronFormValues(raw);
  late final fields = {for (final e in initial.entries) e.key: TextEditingController(text: e.value)};
  late final bool initialNoAgent = raw['no_agent'] == true;
  late bool noAgent = initialNoAgent;
  List<({String id, String name})> targets = [];
  bool saving = false;

  @override
  void initState() {
    super.initState();
    loadTargets();
  }

  @override
  void dispose() {
    for (final f in fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// Delivery targets the server knows (local, and each platform with a home channel).
  Future<void> loadTargets() async {
    try {
      final body = await serverApi('GET', '/api/cron/delivery-targets');
      final j = body == null ? null : jsonDecode(body);
      if (!mounted || j is! Map || j['targets'] is! List) return;
      setState(() {
        targets = [
          for (final t in (j['targets'] as List).whereType<Map>())
            if (t['id'] is String) (id: t['id'] as String, name: '${t['name'] ?? t['id']}'),
        ];
      });
    } catch (e) {
      debugPrint('Cron targets: $e');
    }
  }

  Future<void> save() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final values = {for (final e in fields.entries) e.key: e.value.text};
    final payload = cronPayload(values);
    setState(() => saving = true);
    try {
      if (widget.job case final job?) {
        // only what changed, so untouched fields are not re-validated
        final changed = {
          for (final k in payload.keys)
            if (values[k] != initial[k]) k: payload[k],
          if (noAgent != initialNoAgent) 'no_agent': noAgent,
        };
        if (changed.isNotEmpty) await serverApi('PUT', '/api/cron/jobs/${Uri.encodeComponent(job.id)}', body: {'updates': changed});
      } else {
        // creation doesn't take these; they follow as an update of the new job
        const later = ['failure_deliver', 'monitor_script', 'monitor_url', 'reasoning_effort'];
        final extra = {for (final k in later) k: payload.remove(k)}..removeWhere((_, v) => v == '');
        final body = await serverApi('POST', '/api/cron/jobs', body: {...payload, 'no_agent': noAgent});
        final id = switch (body == null ? null : jsonDecode(body)) {
          {'id': final String id} || {'job': {'id': final String id}} => id,
          _ => null,
        };
        if (extra.isNotEmpty && id != null) await serverApi('PUT', '/api/cron/jobs/${Uri.encodeComponent(id)}', body: {'updates': extra});
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Cron save: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.cronActionFailed(e is HttpException ? e.message : '$e'))));
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> delete() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showChoices<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(widget.job!.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        message: Text(l.cronDeleteMessage),
        actions: [
          CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: Text(l.cronDelete)),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => saving = true);
    try {
      await serverApi('DELETE', '/api/cron/jobs/${Uri.encodeComponent(widget.job!.id)}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Cron delete: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.cronActionFailed(e is HttpException ? e.message : '$e'))));
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> pickTarget() async {
    final id = await showChoices<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [for (final t in targets) CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, t.id), child: Text(t.name))],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).cancel)),
      ),
    );
    if (id != null) fields['deliver']!.text = id;
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

    Widget field(String key, String label, {String? hint, int maxLines = 1, bool prose = false, Widget? trailing}) => Padding(
      padding: EdgeInsets.fromLTRB(16, 10, trailing == null ? 16 : 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: small),
                const SizedBox(height: 4),
                TextField(
                  controller: fields[key],
                  minLines: 1,
                  maxLines: maxLines,
                  autocorrect: prose,
                  enableSuggestions: prose,
                  textCapitalization: prose ? TextCapitalization.sentences : TextCapitalization.none,
                  style: TextStyle(fontSize: 16, color: c.onSurface),
                  decoration: InputDecoration.collapsed(
                    hintText: hint,
                    hintStyle: TextStyle(fontSize: 16, color: c.outline.withValues(alpha: .6)),
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );

    final done = switch (raw['repeat']) {
      {'completed': final int n} when n > 0 => n,
      _ => 0,
    };
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 52,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 120), // clear of both buttons
                    child: Text(
                      widget.job == null ? l.cronNew : l.cronEdit,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: Icon(CupertinoIcons.chevron_back, color: c.onSurface),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    child: saving
                        ? const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: CupertinoActivityIndicator())
                        : TextButton(
                            onPressed: save,
                            child: Text(l.cronSave, maxLines: 1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: 48),
                children: [
                  if (widget.job case final job?)
                    section('', [
                      Hover(
                        radius: 0,
                        child: CupertinoListTile(
                          title: Text(l.cronRuns, style: TextStyle(fontSize: 16, color: c.onSurface)),
                          trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: c.outline),
                          onTap: () => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => CronRunsPage(job: job))),
                        ),
                      ),
                    ]),
                  section(l.cronGeneral, [
                    field('name', l.cronName, maxLines: 3, prose: true),
                    field('schedule', l.cronSchedule, hint: '0 9 * * *'),
                    field('repeat', l.cronRepeat, hint: l.cronRepeatHint),
                  ], footer: [l.cronScheduleHint, if (done > 0) l.cronRepeatDone(done)].join('\n')),
                  section(l.cronTask, [
                    field('prompt', l.cronPrompt, maxLines: 12, prose: true),
                    field('script', l.cronScript, hint: l.cronScriptHint),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(l.cronNoAgent, style: TextStyle(fontSize: 16, color: c.onSurface)),
                          ),
                          CupertinoSwitch(value: noAgent, onChanged: (v) => setState(() => noAgent = v)),
                        ],
                      ),
                    ),
                    field('skills', l.cronSkills, hint: l.cronListHint),
                  ]),
                  section(l.cronModelSection, [
                    ModelTile(
                      model: jobModel({'provider': fields['provider']!.text, 'model': fields['model']!.text}),
                      effort: fields['reasoning_effort']!.text,
                      onModel: (id) => setState(() {
                        final u = jobModelUpdates(id);
                        fields['provider']!.text = '${u['provider'] ?? ''}';
                        fields['model']!.text = '${u['model'] ?? ''}';
                      }),
                      onEffort: (e) => setState(() => fields['reasoning_effort']!.text = e),
                    ),
                    field('base_url', l.cronBaseUrl, hint: l.cronServerDefault),
                  ]),
                  section(l.cronDelivery, [
                    field(
                      'deliver',
                      l.cronDeliver,
                      trailing: targets.isEmpty
                          ? null
                          : IconButton(
                              onPressed: pickTarget,
                              icon: Icon(CupertinoIcons.chevron_up_chevron_down, size: 18, color: c.outline),
                            ),
                    ),
                    field('failure_deliver', l.cronFailureDeliver, hint: l.cronFailureHint),
                  ]),
                  section(l.cronMonitor, [
                    field('monitor_script', l.cronMonitorScript, hint: l.cronScriptHint),
                    field('monitor_url', l.cronMonitorUrl, hint: 'https://'),
                  ], footer: l.cronMonitorHint),
                  section(l.cronAdvanced, [
                    field('workdir', l.cronWorkdir),
                    field('enabled_toolsets', l.cronToolsets, hint: l.cronListHint),
                    field('context_from', l.cronContextFrom, hint: l.cronContextHint),
                  ]),
                  if (widget.job != null)
                    section('', [
                      Hover(
                        radius: 0,
                        child: CupertinoListTile(
                          onTap: saving ? null : delete,
                          title: Center(
                            child: Text(l.cronDelete, style: const TextStyle(fontSize: 16, color: CupertinoColors.systemRed)),
                          ),
                        ),
                      ),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A run's title and preview, the preview left out when the title already quotes it.
String runText(CronRun r, String separator) =>
    [r.title, if (!r.title.contains(r.preview)) r.preview].where((t) => t.trim().isNotEmpty).join(separator);

/// A job's past runs, newest first; a run opens on what it produced.
class CronRunsPage extends StatefulWidget {
  const CronRunsPage({super.key, required this.job});
  final CronJob job;

  @override
  State<CronRunsPage> createState() => _CronRunsPageState();
}

class _CronRunsPageState extends State<CronRunsPage> {
  List<CronRun>? runs;
  Object? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final body = await serverApi('GET', '/api/cron/jobs/${Uri.encodeComponent(widget.job.id)}/runs');
      if (mounted) setState(() => runs = parseCronRuns(body ?? ''));
    } catch (e) {
      debugPrint('Cron runs: $e');
      if (mounted) setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    final format = DateFormat.MMMd(Localizations.localeOf(context).toString()).add_Hm();
    final list = runs;
    return PageFrame(
      title: l.cronRuns,
      child: switch ((list, error)) {
        (_, final Object e) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              serverErrorText(l, e),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.onSurfaceVariant),
            ),
          ),
        ),
        (null, _) => const Center(child: CupertinoActivityIndicator()),
        (final List<CronRun> list, _) when list.isEmpty => Center(
          child: Text(l.cronRunsEmpty, style: TextStyle(color: c.onSurfaceVariant)),
        ),
        (final List<CronRun> list, _) => RefreshIndicator(
          onRefresh: load,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 48),
            children: [
              CupertinoListSection.insetGrouped(
                backgroundColor: c.surface,
                decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                separatorColor: c.outline.withValues(alpha: .2),
                children: [
                  for (final r in list)
                    Hover(
                      radius: 0,
                      child: CupertinoListTile(
                        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                        title: Text(
                          [if (r.at != null) format.format(r.at!), if (r.active) l.cronRunning].join(' · '),
                          style: TextStyle(fontSize: 16, color: c.onSurface),
                        ),
                        subtitle: Text(runText(r, ' — '), maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
                        trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: c.outline),
                        onTap: () => Navigator.of(context).push(
                          CupertinoPageRoute<void>(
                            builder: (_) => _CronRunPage(run: r, job: widget.job, title: r.at == null ? l.cronRuns : format.format(r.at!)),
                          ),
                        ),
                      ),
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

/// What one run produced: its final reply (an agent run), or the output the server kept.
class _CronRunPage extends StatefulWidget {
  const _CronRunPage({required this.run, required this.job, required this.title});
  final CronRun run;
  final CronJob job;
  final String title;

  @override
  State<_CronRunPage> createState() => _CronRunPageState();
}

class _CronRunPageState extends State<_CronRunPage> {
  String? text;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = widget.run;
    var out = runText(r, '\n\n');
    if (r.session) {
      try {
        final body = await serverApi('GET', '/api/sessions/${Uri.encodeComponent(r.id)}/messages');
        final reply = transcript((jsonDecode(body ?? '{}') as Map)['messages']).lastWhere((m) => !m.user, orElse: () => Msg(false, ''));
        if (reply.text.trim().isNotEmpty) out = reply.text.trim();
      } catch (e) {
        debugPrint('Cron run: $e');
      }
    } else if (cronOutputPath(r, '${widget.job.raw['hermes_home'] ?? ''}') case final path?) {
      try {
        final file = jsonDecode(await serverApi('GET', '/api/files/read', query: {'path': path}) ?? '{}') as Map;
        if (file['data_url'] case final String url) {
          final text = cronOutputText(utf8.decode(UriData.parse(url).contentAsBytes(), allowMalformed: true));
          if (text.isNotEmpty) out = text;
        }
      } catch (e) {
        debugPrint('Cron output: $e'); // the preview stays
      }
    }
    if (mounted) setState(() => text = out);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return PageFrame(
      title: widget.title,
      child: text == null
          ? const Center(child: CupertinoActivityIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
              child: SelectableText(text!, style: TextStyle(fontSize: 16, height: 1.45, color: c.onSurface)),
            ),
    );
  }
}

/// A pushed page: back button, centered title, an optional [action] on the right, [child] below.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.title, required this.child, this.action, this.full = false});
  final String title;
  final Widget child;
  final Widget? action;
  final bool full; // the whole width, not a readable column

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 52,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: action == null ? 56 : 116), // clear of a text button
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(CupertinoIcons.chevron_back, color: c.onSurface),
                    ),
                  ),
                  if (action != null) Positioned(right: 4, child: action!),
                ],
              ),
            ),
            Expanded(child: full ? child : readable(child)),
          ],
        ),
      ),
    );
  }
}
