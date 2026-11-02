import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'cron_page.dart';
import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';

const _api = '/api/plugins/kanban';

/// Why a card waits for the user, as a short tag.
String attentionText(AppLocalizations l, String attention) => switch (attention) {
  'review' => l.kanbanToReview,
  'blocked' => l.kanbanIsBlocked,
  'decision' => l.kanbanDecision,
  _ => attention, // a server diagnostic's own title
};

/// The Kanban cards waiting for the user, and a way to drop a new idea in Triage.
class KanbanPage extends StatefulWidget {
  const KanbanPage({super.key});

  @override
  State<KanbanPage> createState() => _KanbanPageState();
}

class _KanbanPageState extends State<KanbanPage> {
  List<KCard>? cards;
  Board? board;
  Object? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final body = await serverApi('GET', '$_api/board');
      if (body == null) throw StateError('no server');
      if (!mounted) return;
      setState(() {
        cards = parseAttention(body);
        board = parseBoard(body);
        error = null;
      });
    } catch (e) {
      debugPrint('Kanban: $e');
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> open(Widget page) async {
    final changed = await Navigator.of(context).push<bool>(CupertinoPageRoute(builder: (_) => page));
    if (changed == true) load();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    final list = cards;
    final counts = [
      for (final (status, text) in [
        ('ready', l.kanbanReady),
        ('todo', l.kanbanTodo),
        ('review', l.kanbanReview),
        ('blocked', l.kanbanBlocked),
        ('done', l.kanbanDone),
      ])
        if ((board?.counts[status] ?? 0) > 0) text(board!.counts[status]!),
    ];
    return PageFrame(
      title: l.kanban,
      action: error == null
          ? IconButton(
              tooltip: l.kanbanAdd,
              onPressed: () => open(const KanbanAddPage()),
              icon: Icon(CupertinoIcons.add, color: c.onSurface),
            )
          : null,
      child: list == null && error == null
          ? const Center(child: CupertinoActivityIndicator())
          : RefreshIndicator.adaptive(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 48),
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
                      child: Text(
                        serverErrorText(l, error is StateError ? null : error),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: c.outline),
                      ),
                    )
                  else
                    CupertinoListSection.insetGrouped(
                      backgroundColor: c.surface,
                      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                      separatorColor: c.outline.withValues(alpha: .2),
                      header: Text(l.kanbanYourTurn.toUpperCase(), style: small),
                      footer: counts.isEmpty ? null : Text(counts.join(' · '), style: small),
                      children: [
                        if (list!.isEmpty)
                          CupertinoListTile(
                            title: Text(l.kanbanNothing, style: TextStyle(fontSize: 16, color: c.outline)),
                          ),
                        for (final k in list)
                          Hover(
                            radius: 0,
                            child: CupertinoListTile(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                              title: Text(k.title, maxLines: 2, style: TextStyle(fontSize: 16, color: c.onSurface)),
                              subtitle: Text(
                                [attentionText(l, k.attention), if (k.comments > 0) '💬 ${k.comments}'].join(' · '),
                                style: TextStyle(fontSize: 13, color: k.attention == 'blocked' ? CupertinoColors.systemOrange : c.outline),
                              ),
                              trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: c.outline),
                              onTap: () => open(KanbanCardPage(id: k.id, title: k.title)),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

/// A card in full: its description, latest summary and history, with a reply box and, for a card in
/// review or blocked, approving it or sending it back. Pops true once the card changed.
class KanbanCardPage extends StatefulWidget {
  const KanbanCardPage({super.key, required this.id, required this.title});
  final String id, title;

  @override
  State<KanbanCardPage> createState() => _KanbanCardPageState();
}

class _KanbanCardPageState extends State<KanbanCardPage> {
  final reply = TextEditingController();
  ({KCard card, List<KNote> notes})? detail;
  Object? error;
  var busy = false;
  var changed = false;

  String get path => '$_api/tasks/${Uri.encodeComponent(widget.id)}';

  @override
  void initState() {
    super.initState();
    reply.addListener(() => setState(() {}));
    load();
  }

  @override
  void dispose() {
    reply.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final body = await serverApi('GET', path);
      if (body == null) throw StateError('no server');
      if (mounted) setState(() => detail = parseCard(body));
    } catch (e) {
      debugPrint('Kanban card: $e');
      if (mounted) setState(() => error = e);
    }
  }

  /// Runs the server [steps] in order, then reloads the card; false when one failed.
  Future<bool> run(List<Future<Object?> Function()> steps) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      for (final s in steps) {
        await s();
      }
      changed = true;
      await load();
      return true;
    } catch (e) {
      debugPrint('Kanban action: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.cronActionFailed(e is HttpException ? e.message : serverErrorText(l, null)))));
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Object?> comment() => serverApi('POST', '$path/comments', body: {'body': reply.text.trim()});

  Future<void> send() async {
    if (await run([comment])) reply.clear();
  }

  Future<void> act() async {
    final l = AppLocalizations.of(context);
    final review = detail?.card.status == 'review';
    final status = await showChoices<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        message: Text(l.kanbanSendBackMessage),
        actions: [
          if (review) CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, 'done'), child: Text(l.kanbanApprove)),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, 'ready'), child: Text(l.kanbanSendBack)),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
      ),
    );
    if (status == null || !mounted) return;
    final ok = await run([
      if (reply.text.trim().isNotEmpty) comment,
      () => serverApi('PATCH', path, body: {'status': status}),
    ]);
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    final d = detail;
    final locale = '${Localizations.localeOf(context)}';
    String when(DateTime? t) => t == null ? '' : DateFormat.MMMd(locale).add_Hm().format(t);
    Widget block(String title, Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 6),
            child: Text(title.toUpperCase(), style: small),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
            child: child,
          ),
        ],
      ),
    );
    final text = TextStyle(fontSize: 15, height: 1.4, color: c.onSurface);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) Navigator.pop(context, changed);
      },
      child: PageFrame(
        title: widget.title,
        action: d != null && (d.card.status == 'review' || d.card.status == 'blocked') && !busy
            ? IconButton(
                tooltip: AppLocalizations.of(context).kanbanApprove,
                onPressed: act,
                icon: Icon(CupertinoIcons.checkmark_seal, color: c.onSurface),
              )
            : busy
            ? const Padding(padding: EdgeInsets.all(14), child: CupertinoActivityIndicator())
            : null,
        child: d == null
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
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(36, 8, 36, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                d.card.title,
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.onSurface),
                              ),
                              if (d.card.attention.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(attentionText(l, d.card.attention), style: small),
                              ],
                            ],
                          ),
                        ),
                        if (d.card.body.isNotEmpty) block(l.kanbanDescription, SelectableText(d.card.body, style: text)),
                        if (d.card.summary.isNotEmpty) block(l.kanbanSummary, SelectableText(d.card.summary, style: text)),
                        if (d.notes.isNotEmpty)
                          block(
                            l.kanbanHistory,
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final (i, n) in d.notes.indexed) ...[
                                  if (i > 0) Divider(height: 24, color: c.outline.withValues(alpha: .2)),
                                  Text(
                                    [
                                      switch (n.event) {
                                        '' => n.author,
                                        'review_requested' => l.kanbanReviewRequested,
                                        'completed' => l.kanbanCompleted,
                                        'blocked' => l.kanbanIsBlocked,
                                        final e => e,
                                      },
                                      when(n.at),
                                    ].where((s) => s.isNotEmpty).join(' · '),
                                    style: small,
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(n.text, style: text),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                              child: TextField(
                                controller: reply,
                                maxLines: 5,
                                minLines: 1,
                                style: TextStyle(fontSize: 16, color: c.onSurface),
                                decoration: InputDecoration.collapsed(
                                  hintText: l.kanbanReplyHint,
                                  hintStyle: TextStyle(fontSize: 16, color: c.outline),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: l.kanbanReplyHint,
                            onPressed: reply.text.trim().isEmpty || busy ? null : send,
                            icon: Icon(
                              CupertinoIcons.arrow_up_circle_fill,
                              size: 32,
                              color: reply.text.trim().isEmpty ? c.outline : c.onSurface,
                            ),
                          ),
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

/// A new idea for the board, dropped in Triage; pops true once created.
class KanbanAddPage extends StatefulWidget {
  const KanbanAddPage({super.key});

  @override
  State<KanbanAddPage> createState() => _KanbanAddPageState();
}

class _KanbanAddPageState extends State<KanbanAddPage> {
  final title = TextEditingController(), details = TextEditingController();
  var saving = false;

  @override
  void initState() {
    super.initState();
    title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    title.dispose();
    details.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => saving = true);
    try {
      await serverApi(
        'POST',
        '$_api/tasks',
        body: {'title': title.text.trim(), if (details.text.trim().isNotEmpty) 'body': details.text.trim(), 'triage': true},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Kanban add: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.cronActionFailed(e is HttpException ? e.message : serverErrorText(l, null)))));
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    Widget field(String name, TextEditingController controller, {bool long = false}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: small),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            autofocus: !long,
            maxLines: long ? null : 1,
            minLines: long ? 4 : 1,
            style: TextStyle(fontSize: 16, color: c.onSurface),
            decoration: const InputDecoration.collapsed(hintText: null),
          ),
        ],
      ),
    );
    return PageFrame(
      title: l.kanbanAdd,
      action: saving
          ? const Padding(padding: EdgeInsets.all(14), child: CupertinoActivityIndicator())
          : TextButton(
              onPressed: title.text.trim().isEmpty ? null : save,
              child: Text(l.cronSave, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          CupertinoListSection.insetGrouped(
            backgroundColor: c.surface,
            decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
            separatorColor: c.outline.withValues(alpha: .2),
            footer: Text(l.kanbanAddFooter, style: small),
            children: [field(l.kanbanTitle, title), field(l.kanbanDetails, details, long: true)],
          ),
        ],
      ),
    );
  }
}
