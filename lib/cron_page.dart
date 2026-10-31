import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'quota_page.dart';
import 'settings.dart';

/// The server's scheduled jobs: pause / resume them, or run one now.
class CronPage extends StatefulWidget {
  const CronPage({super.key});

  @override
  State<CronPage> createState() => _CronPageState();
}

class _CronPageState extends State<CronPage> {
  List<CronJob>? jobs;
  Object? error;
  bool failed = false;
  final busy = <String>{}; // job ids with a request in flight

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final body = await serverApi('GET', '/api/cron/jobs');
      if (!mounted) return;
      setState(() {
        jobs = body == null ? null : parseCronJobs(body);
        failed = body == null;
        error = null;
      });
    } catch (e) {
      debugPrint('Cron: $e');
      if (!mounted) return;
      setState(() {
        failed = true;
        error = e;
      });
    }
  }

  /// Posts [action] (`pause`, `resume`, `trigger`) for [job], then refreshes the list.
  Future<void> act(CronJob job, String action) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy.add(job.id));
    try {
      await serverApi('POST', '/api/cron/jobs/${Uri.encodeComponent(job.id)}/$action');
      if (action == 'trigger') messenger.showSnackBar(SnackBar(content: Text(l.cronStarted(job.name))));
    } on TimeoutException {
      // a run can outlast the request; it goes on on the server
      if (action == 'trigger') messenger.showSnackBar(SnackBar(content: Text(l.cronStarted(job.name))));
    } catch (e) {
      debugPrint('Cron $action: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.cronActionFailed(e is HttpException ? e.message : '$e'))));
    }
    if (!mounted) return;
    await load();
    if (mounted) setState(() => busy.remove(job.id));
  }

  /// Opens the editor for [job] (a new one when null), then refreshes if something changed.
  Future<void> edit(CronJob? job) async {
    final changed = await Navigator.of(context).push<bool>(CupertinoPageRoute(builder: (_) => CronEditPage(job: job)));
    if (changed == true) load();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
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
                  Text(
                    l.cron,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                  ),
                  if (!failed)
                    Positioned(
                      right: 4,
                      child: IconButton(
                        tooltip: l.cronNew,
                        onPressed: () => edit(null),
                        icon: Icon(CupertinoIcons.add, color: c.onSurface),
                      ),
                    ),
                  Positioned(
                    left: 4,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(CupertinoIcons.chevron_back, color: c.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: jobs == null && !failed
                  ? const Center(child: CupertinoActivityIndicator())
                  : RefreshIndicator.adaptive(
                      onRefresh: load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 32),
                        children: [
                          if (failed || jobs!.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
                              child: Text(
                                failed ? serverErrorText(l, error) : l.cronEmpty,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 15, color: c.outline),
                              ),
                            )
                          else ...[
                            CupertinoListSection.insetGrouped(
                              backgroundColor: c.surface,
                              decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                              separatorColor: c.outline.withValues(alpha: .2),
                              children: [
                                for (final j in jobs!)
                                  _CronTile(
                                    j,
                                    busy: busy.contains(j.id),
                                    onToggle: (on) => act(j, on ? 'resume' : 'pause'),
                                    onRun: () => act(j, 'trigger'),
                                    onTap: () => edit(j),
                                  ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(36, 4, 36, 0),
                              child: Text(l.cronFooter, style: TextStyle(fontSize: 13, color: c.outline)),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CronTile extends StatelessWidget {
  const _CronTile(this.job, {required this.busy, required this.onToggle, required this.onRun, required this.onTap});
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
    return GestureDetector(
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
        await serverApi('POST', '/api/cron/jobs', body: {...payload..remove('failure_deliver'), 'no_agent': noAgent});
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
    final ok = await showCupertinoModalPopup<bool>(
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
    final id = await showCupertinoModalPopup<String>(
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
                    field('model', l.cronModel, hint: l.cronServerDefault),
                    field('provider', l.cronProvider, hint: l.cronServerDefault),
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
                  section(l.cronAdvanced, [
                    field('workdir', l.cronWorkdir),
                    field('enabled_toolsets', l.cronToolsets, hint: l.cronListHint),
                    field('context_from', l.cronContextFrom, hint: l.cronContextHint),
                  ]),
                  if (widget.job != null)
                    section('', [
                      CupertinoListTile(
                        onTap: saving ? null : delete,
                        title: Center(
                          child: Text(l.cronDelete, style: const TextStyle(fontSize: 16, color: CupertinoColors.systemRed)),
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
