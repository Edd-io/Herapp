part of 'chat_page.dart';

/// How a conversation shows: messages, tool calls, approvals and the cards a reply brings.
extension _Messages on _ChatPageState {
  /// Under an empty chat's headline: a few things to ask, which fill the composer, and what runs now
  /// (subagents at work, the scheduled jobs' results), a tap away.
  Widget _welcome(ColorScheme c) {
    Widget chip(String text, {IconData? icon, required VoidCallback onTap}) => Hover(
      radius: 18,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: c.outline.withValues(alpha: .35)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 15, color: c.primary), const SizedBox(width: 7)],
              Flexible(
                child: Text(text, style: TextStyle(fontSize: 14, color: c.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
    void suggest(String text) {
      input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      focus.requestFocus();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in [l.suggestRoutines, l.suggestSchedule, l.suggestKanban, l.suggestWeb]) chip(s, onTap: () => suggest(s)),
            ],
          ),
          ValueListenableBuilder(
            valueListenable: subagents,
            builder: (context, all, _) {
              final working = all.values.where(subagentRunning).length;
              if (working == 0 && bot == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  children: [
                    Text(l.welcomeNow, style: TextStyle(fontSize: 12, color: c.outline)),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (working > 0)
                          chip(l.welcomeSubagents(working), icon: CupertinoIcons.sparkles, onTap: () => openPage(const AgentsPage())),
                        if (bot case final b?) chip(l.welcomeRoutines, icon: CupertinoIcons.clock, onTap: () => select(b)),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _message(ColorScheme c, Msg m, bool last) {
    const body = TextStyle(fontSize: 17, height: 1.45);
    if (m.user) {
      if (cronDelivery(m.text) case final d?) return _routine(c, d);
      if (m.text.startsWith(macResultTag)) return _MacResult(m.text);
      final actions = !streaming && !queue.contains(m); // a turn running, or the message waiting, can't be redone yet
      final text = Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: EdgeInsets.only(left: 64, top: 12, bottom: actions ? 2 : 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(22)),
          child: m.files.isEmpty
              ? Text(m.text, style: body.copyWith(color: c.onSurface))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [for (final f in m.files) _Attachment(f)]),
                    if (m.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(m.text, style: body.copyWith(color: c.onSurface)),
                      ),
                  ],
                ),
        ),
      );
      final bubble = !actions
          ? text
          : _Hovered(
              builder: (shown) => Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  text,
                  _reveal(
                    shown,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _IconBtn(
                          small: true,
                          label: l.a11yEdit,
                          onTap: () => edit(m),
                          child: Icon(CupertinoIcons.pencil, size: 18, color: c.onSurfaceVariant),
                        ),
                        _IconBtn(
                          small: true,
                          label: l.a11yResend,
                          onTap: () => resend(m),
                          child: Icon(CupertinoIcons.arrow_2_circlepath, size: 18, color: c.onSurfaceVariant),
                        ),
                        if (hovers) Text(_time(m.at), style: TextStyle(fontSize: 12, color: c.outline)),
                      ],
                    ),
                  ),
                ],
              ),
            );
      if (!identical(m, fresh)) return bubble;
      return TweenAnimationBuilder<double>(
        key: ObjectKey(m),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        onEnd: () => fresh = null,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
        ),
        child: bubble,
      );
    }
    final live = last && streaming;
    // the steps it asks of this computer show as cards, under its words
    final steps = macOn ? macSteps(m.text, settings.macToken) : const <MacStep>[];
    final text = steps.isEmpty ? m.text : withoutMacSteps(m.text, settings.macToken);
    return _Hovered(
      builder: (shown) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // who answers, as a messaging app names the sender; when, on hover (always on a touch screen)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                    child: Icon(CupertinoIcons.sparkles, size: 13, color: c.onPrimary),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      switch (m.model.isNotEmpty ? m.model : chat.model) {
                        '' => 'Herapp',
                        final id => modelName(id),
                      },
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.onSurface),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedOpacity(
                    opacity: shown || !hovers ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Text(_time(m.at), style: TextStyle(fontSize: 12, color: c.outline)),
                  ),
                ],
              ),
            ),
            if (m.tools.isNotEmpty) _Tools(m.tools, live: live),
            // its browser runs on the bot's screen: watched as it goes, taken over for a CAPTCHA
            if (last && m.tools.any((t) => t.name.startsWith('browser') || t.name == 'computer_use'))
              _ScreenPreview(live: live, onOpen: () => show(const ScreenPage())),
            for (final t in m.tools.where((t) => t.done))
              if (memoryChanges(t) case final changes when changes.isNotEmpty) _memoryCard(c, changes),
            if (m.ask case final ask?)
              ask.kind == 'approval'
                  ? _approval(c, m, ask.params)
                  : _Ask(
                      ask,
                      key: ObjectKey(ask), // a new request, a fresh card
                      onAnswer: (r) => answer(m, r),
                      choice: (label, onTap, main, danger) => _choice(c, label, onTap, main: main, danger: danger),
                    ),
            if (text.trim().isNotEmpty)
              _Markdown(text.trimLeft(), style: body.copyWith(color: c.onSurface)) // text after a tool call starts with blank lines
            else if (live && m.ask == null && m.tools.every((t) => t.done))
              _PulseDot(c.onSurface),
            for (final (i, s) in steps.indexed) _macCard(c, s, m.mac.elementAtOrNull(i)),
            if (!live && m.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                // the latest reply's actions stay in sight; the others come with the mouse
                child: _reveal(
                  shown || last,
                  Row(
                    children: [
                      _IconBtn(
                        small: true,
                        label: l.a11yCopy,
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: m.text.trim()));
                          settings.haptic();
                        },
                        child: Icon(CupertinoIcons.doc_on_doc, size: 18, color: c.onSurfaceVariant),
                      ),
                      ListenableBuilder(
                        listenable: voice,
                        builder: (context, _) => _IconBtn(
                          small: true,
                          label: identical(voice.reading, m) ? l.a11yStopReading : l.a11yRead,
                          onTap: () => voice.read(m, text),
                          child: Icon(
                            identical(voice.reading, m) ? CupertinoIcons.stop_circle : CupertinoIcons.speaker_2,
                            size: 18,
                            color: c.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (last)
                        _IconBtn(
                          small: true,
                          label: l.a11yRegenerate,
                          onTap: regenerate,
                          child: Icon(CupertinoIcons.arrow_2_circlepath, size: 18, color: c.onSurfaceVariant),
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

  /// A computer shows a message's actions and time on hover; a touch screen, always.
  bool get hovers => const [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux].contains(defaultTargetPlatform);

  /// [child], in sight when [shown] (or on a touch screen); its room is kept, so nothing jumps.
  Widget _reveal(bool shown, Widget child) {
    final on = shown || !hovers;
    return IgnorePointer(
      ignoring: !on,
      child: AnimatedOpacity(opacity: on ? 1 : 0, duration: const Duration(milliseconds: 150), child: child),
    );
  }

  String _time(DateTime at) => DateFormat.Hm('${Localizations.localeOf(context)}').format(at);

  /// A message waiting for the reply before it; a tap takes it back to edit.
  Widget _queued(ColorScheme c, Msg m) => GestureDetector(
    onTap: () => unqueue([m]),
    child: Opacity(
      opacity: .55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _message(c, m, false),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(AppLocalizations.of(context).queued, style: TextStyle(fontSize: 12, color: c.outline)),
          ),
        ],
      ),
    ),
  );

  /// A scheduled job's result delivered into the chat for Hermes to read: the job's words, not the user's.
  Widget _routine(ColorScheme c, ({String job, String output}) d) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: c.surfaceContainerHighest, width: 1.5),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(CupertinoIcons.clock, size: 14, color: c.outline),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                AppLocalizations.of(context).routineResult(d.job).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .4, color: c.outline),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Markdown(d.output.trim(), style: TextStyle(fontSize: 15, height: 1.4, color: c.onSurface)),
      ],
    ),
  );

  /// What a reply wrote to Hermes' memory (struck through when forgotten); a tap opens the memory.
  Widget _memoryCard(ColorScheme c, List<(String, bool)> changes) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Hover(
      radius: 14,
      child: GestureDetector(
        onTap: () => show(const MemoryPage()),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(CupertinoIcons.lightbulb, size: 14, color: c.outline),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context).memoryUpdated.toUpperCase(),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .4, color: c.outline),
                  ),
                ],
              ),
              for (final (text, gone) in changes)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      color: gone ? c.outline : c.onSurface,
                      decoration: gone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  /// The card asking whether Hermes may run a command, with the choices the server allows.
  Widget _approval(ColorScheme c, Msg m, Map p) {
    final l = AppLocalizations.of(context);
    final choices = [
      for (final k
          in p['choices'] is List && (p['choices'] as List).isNotEmpty ? p['choices'] as List : const ['once', 'session', 'always', 'deny'])
        if (!(k == 'session' && p['allow_session'] == false) && !(k == 'always' && p['allow_permanent'] == false)) '$k',
    ];
    Widget button(String k) => _choice(
      c,
      switch (k) {
        'once' => l.approveOnce,
        'session' => l.approveSession,
        'always' => l.approveAlways,
        'deny' => l.approveDeny,
        _ => k,
      },
      () => answer(m, {'choice': k}),
      main: k == 'once',
      danger: k == 'deny',
    );

    final command = '${p['command'] ?? ''}'.trim(), description = '${p['description'] ?? ''}'.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.approvalTitle,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onSurface),
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(description, style: TextStyle(fontSize: 14, color: c.onSurfaceVariant)),
            ),
          if (command.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10)),
              child: SelectableText(
                command,
                style: TextStyle(fontFamily: 'Menlo', fontSize: 13, color: c.onSurface),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final k in choices) button(k)]),
        ],
      ),
    );
  }

  /// One of the choices a card offers; [main] is the one expected, [danger] the one that declines.
  Widget _choice(ColorScheme c, String label, VoidCallback onTap, {bool main = false, bool danger = false}) => Hover(
    radius: 10,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: main ? c.primary : c.surface, borderRadius: BorderRadius.circular(20)),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: main ? c.onPrimary : (danger ? const Color(0xFFD93025) : c.onSurface),
          ),
        ),
      ),
    ),
  );

  /// A step a reply asks of this computer: what it runs or writes, what it printed, and the choices while it waits.
  Widget _macCard(ColorScheme c, MacStep s, MacRun? r) {
    final l = AppLocalizations.of(context);
    final mono = TextStyle(fontFamily: 'Menlo', fontFamilyFallback: const ['Courier'], fontSize: 13, color: c.onSurface);
    final faint = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.outline);
    Widget box(String text, {bool end = false}) => Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 240),
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10)),
      // an output stays scrolled to its end, where it goes on
      child: SingleChildScrollView(
        reverse: end,
        padding: const EdgeInsets.all(10),
        child: SelectableText(text, style: mono),
      ),
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(s.path.isEmpty ? CupertinoIcons.desktopcomputer : CupertinoIcons.doc_text, size: 14, color: c.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(s.path.isEmpty ? l.macTitle : l.macWrite(s.path), maxLines: 1, overflow: TextOverflow.ellipsis, style: faint),
              ),
              ?switch (r) {
                MacRun(state: 'running') => const CupertinoActivityIndicator(radius: 7),
                MacRun(state: 'done', code: 0) => Icon(CupertinoIcons.checkmark_alt, size: 15, color: c.outline),
                MacRun(state: 'done', :final code) => Text('✗ $code', style: faint.copyWith(color: const Color(0xFFD93025))),
                MacRun(state: 'refused') => Text(l.macRefused, style: faint),
                MacRun(state: 'skipped') => Text(l.macSkipped, style: faint),
                _ => null,
              },
            ],
          ),
          box(s.path.isEmpty ? s.script : s.content),
          if (r != null && r.out.trim().isNotEmpty) box(r.out.trimRight(), end: true),
          if (r?.state == 'ask')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _choice(c, l.macRun, () => decide(r!, true), main: true),
                  // what can do real harm is asked for every time
                  if (!macRisky(s, home: MacShell.home, cwd: chat.shell.cwd)) _choice(c, l.macAlways, () => decide(r!, true, always: true)),
                  _choice(c, l.macRefuse, () => decide(r!, false), danger: true),
                ],
              ),
            ),
          if (r?.state == 'running' && s.path.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 12), child: _choice(c, l.macStop, chat.shell.stop, danger: true)),
        ],
      ),
    );
  }
}

/// A photo's thumbnail, or a file's name; [onRemove] adds the button that takes it off a draft.
class _Attachment extends StatelessWidget {
  const _Attachment(this.file, {this.onRemove});
  final Attachment file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final bytes = file.bytes;
    final tile = file.image && bytes != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, width: 64, height: 64, fit: BoxFit.cover, cacheWidth: 192),
          )
        : Container(
            height: 64,
            constraints: const BoxConstraints(maxWidth: 180, minWidth: 64),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(file.image ? CupertinoIcons.photo : CupertinoIcons.doc, size: 20, color: c.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.onSurface),
                  ),
                ),
              ],
            ),
          );
    if (onRemove == null) return tile;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        Positioned(
          top: -6,
          right: -6,
          child: Hover(
            radius: 999,
            label: AppLocalizations.of(context).a11yRemove,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: c.onSurface, shape: BoxShape.circle),
                child: Icon(CupertinoIcons.xmark, size: 12, color: c.surface),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// An icon for what a tool does, by its name.
IconData toolIcon(String name) => switch (name.toLowerCase()) {
  final n when n.contains('search') || n.startsWith('web') => CupertinoIcons.globe,
  final n when n.startsWith('browser') || n == 'computer_use' => CupertinoIcons.compass,
  final n when n.contains('write') || n.contains('patch') || n.contains('edit') => CupertinoIcons.pencil,
  final n when n.contains('read') || n.contains('file') || n.contains('search_files') => CupertinoIcons.doc_text,
  final n when n.contains('terminal') || n.contains('shell') || n.contains('exec') || n.contains('process') =>
    CupertinoIcons.chevron_left_slash_chevron_right,
  final n when n.contains('memory') => CupertinoIcons.lightbulb,
  final n when n.contains('delegate') || n.contains('agent') => CupertinoIcons.sparkles,
  final n when n.contains('image') || n.contains('vision') => CupertinoIcons.photo,
  _ => CupertinoIcons.wrench,
};

/// The steps a reply took, as a timeline: its latest steps while it runs, then one line with a strip of
/// what it used, which unfolds into the whole timeline.
class _Tools extends StatefulWidget {
  const _Tools(this.tools, {required this.live});
  final List<Tool> tools;
  final bool live;

  @override
  State<_Tools> createState() => _ToolsState();
}

class _ToolsState extends State<_Tools> {
  var open = false;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final style = TextStyle(fontSize: 14, color: c.onSurfaceVariant);
    final rail = c.outline.withValues(alpha: .35);
    // one step: its dot on the rail (a spinner while it runs), its tool and what it was given
    Widget step(Tool t, {required bool first, required bool end}) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Expanded(
                  child: Center(child: Container(width: 1.5, color: first ? Colors.transparent : rail)),
                ),
                t.done ? Icon(toolIcon(t.name), size: 13, color: c.onSurfaceVariant) : const CupertinoActivityIndicator(radius: 6),
                Expanded(
                  child: Center(child: Container(width: 1.5, color: end ? Colors.transparent : rail)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: t.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (t.detail.trim().isNotEmpty) TextSpan(text: '  ${t.detail.trim().split('\n').first}'),
                  ],
                ),
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
    Widget timeline(List<Tool> tools) => Column(
      children: [for (final (i, t) in tools.indexed) step(t, first: i == 0, end: i == tools.length - 1)],
    );
    Widget toggle(Widget lead, String text) => Hover(
      radius: 8,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => open = !open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(width: 18, child: Center(child: lead)),
              const SizedBox(width: 8),
              Text(text, style: style),
              const SizedBox(width: 2),
              Icon(open ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down, size: 13, color: c.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );

    final tools = widget.tools;
    if (widget.live) {
      // the last few steps in sight; the earlier ones behind a line that unfolds them
      final hidden = open ? 0 : (tools.length - 3).clamp(0, tools.length);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          children: [
            if (hidden > 0 || open && tools.length > 3)
              toggle(Icon(CupertinoIcons.ellipsis, size: 13, color: c.onSurfaceVariant), open ? l.toolsFold : l.toolsEarlier(hidden)),
            timeline(tools.sublist(hidden)),
          ],
        ),
      );
    }
    // what it used, each tool once with its count: the strip of the folded line
    final used = <String, int>{};
    for (final t in tools) {
      used[t.name] = (used[t.name] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          toggle(Icon(CupertinoIcons.wrench, size: 14, color: c.onSurfaceVariant), l.toolsUsed(tools.length)),
          if (!open)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2, bottom: 2),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final MapEntry(key: name, value: n) in used.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(toolIcon(name), size: 12, color: c.onSurfaceVariant),
                          const SizedBox(width: 5),
                          Text(n > 1 ? '$name ×$n' : name, style: TextStyle(fontSize: 12, color: c.onSurfaceVariant)),
                        ],
                      ),
                    ),
                ],
              ),
            )
          else
            timeline(tools),
        ],
      ),
    );
  }
}

/// A glance at the bot's screen, refreshed while [live]; a tap opens it.
class _ScreenPreview extends StatefulWidget {
  const _ScreenPreview({required this.live, required this.onOpen});
  final bool live;
  final VoidCallback onOpen;

  @override
  State<_ScreenPreview> createState() => _ScreenPreviewState();
}

class _ScreenPreviewState extends State<_ScreenPreview> {
  Uint8List? frame;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    grab();
  }

  @override
  void didUpdateWidget(_ScreenPreview old) {
    super.didUpdateWidget(old);
    if (old.live && !widget.live) grab(); // as the reply left it
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> grab() async {
    timer?.cancel();
    try {
      final g = await gateway();
      final r = await g?.call('display.thumbnail');
      if (r?['data_url'] case final String url when mounted) setState(() => frame = UriData.parse(url).contentAsBytes());
    } catch (e) {
      debugPrint('Screen preview: $e'); // no screen: the link still opens it
    }
    if (mounted && widget.live) timer = Timer(const Duration(seconds: 3), grab);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final frame = this.frame;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Hover(
        child: GestureDetector(
          onTap: widget.onOpen,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              color: c.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.outline.withValues(alpha: .2)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (frame != null) Image.memory(frame, gaplessPlayback: true, fit: BoxFit.cover),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.macwindow, size: 16, color: c.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(AppLocalizations.of(context).screenOpen, style: TextStyle(fontSize: 14, color: c.onSurfaceVariant)),
                      ),
                      Icon(CupertinoIcons.chevron_forward, size: 14, color: c.onSurfaceVariant),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MacResult extends StatefulWidget {
  const _MacResult(this.text);
  final String text;

  @override
  State<_MacResult> createState() => _MacResultState();
}

class _MacResultState extends State<_MacResult> {
  var open = false;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final body = widget.text.replaceFirst(macResultTag, '').replaceFirst('</herapp-mac-result>', '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hover(
            radius: 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => open = !open),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.arrow_turn_down_right, size: 14, color: c.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(AppLocalizations.of(context).macResults, style: TextStyle(fontSize: 14, color: c.onSurfaceVariant)),
                    Icon(open ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down, size: 13, color: c.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
              child: SelectableText(
                body,
                style: TextStyle(fontFamily: 'Menlo', fontFamilyFallback: const ['Courier'], fontSize: 12, color: c.onSurface),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pulsing dot shown while waiting for the first reply chunk.
class _PulseDot extends StatefulWidget {
  const _PulseDot(this.color, {this.size = 13});
  final Color color;
  final double size;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final a = AnimationController(vsync: this, duration: const Duration(milliseconds: 700), value: 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // still when the system asks for less motion
    MediaQuery.disableAnimationsOf(context) ? a.stop() : a.repeat(reverse: true);
  }

  @override
  void dispose() {
    a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: ScaleTransition(
      scale: Tween(begin: .75, end: 1.1).animate(CurvedAnimation(parent: a, curve: Curves.easeInOut)),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    ),
  );
}

/// A reply's Markdown (headings, lists, code, tables, quotes), rendered as it streams in.
class _Markdown extends StatelessWidget {
  const _Markdown(this.text, {required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final mono = TextStyle(fontFamily: 'Menlo', fontFamilyFallback: const ['Courier'], fontSize: style.fontSize! * .85, color: c.onSurface);
    final line = BorderSide(color: c.outline.withValues(alpha: .3));
    return MarkdownBody(
      data: text,
      selectable: true,
      builders: {'pre': _CodeBlock(mono)},
      onTapLink: (_, href, _) {
        // only web and mail links leave the app; anything else a reply writes stays text
        if (Uri.tryParse(href ?? '') case final u? when const ['http', 'https', 'mailto'].contains(u.scheme)) {
          launchUrl(u, mode: LaunchMode.externalApplication);
        }
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: style,
        a: style.copyWith(decoration: TextDecoration.underline, color: accentText(Theme.of(context).colorScheme)),
        h1: style.copyWith(fontSize: style.fontSize! * 1.4, fontWeight: FontWeight.w700),
        h2: style.copyWith(fontSize: style.fontSize! * 1.25, fontWeight: FontWeight.w700),
        h3: style.copyWith(fontSize: style.fontSize! * 1.1, fontWeight: FontWeight.w600),
        h4: style.copyWith(fontWeight: FontWeight.w600),
        listBullet: style,
        blockSpacing: 12,
        code: mono.copyWith(backgroundColor: c.surfaceContainerHighest),
        codeblockPadding: const EdgeInsets.all(14),
        codeblockDecoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
        blockquote: style.copyWith(color: c.onSurfaceVariant),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.outline, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.only(left: 14),
        tableHead: style.copyWith(fontWeight: FontWeight.w600),
        tableBody: style,
        tableBorder: TableBorder(horizontalInside: line, top: line, bottom: line),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        horizontalRuleDecoration: BoxDecoration(border: Border(top: line)),
      ),
    );
  }
}

/// A fenced code block: its language, a copy button and the code colored by [highlight].
class _CodeBlock extends MarkdownElementBuilder {
  _CodeBlock(this.mono);
  final TextStyle mono;

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final code = element.textContent.replaceFirst(RegExp(r'\n$'), '');
    final lang = switch (element.children?.firstOrNull) {
      md.Element(attributes: {'class': final String k}) when k.startsWith('language-') => k.substring(9),
      _ => '',
    };
    return _Code(code: code, lang: lang, mono: mono);
  }
}

class _Code extends StatefulWidget {
  const _Code({required this.code, required this.lang, required this.mono});
  final String code, lang;
  final TextStyle mono;

  @override
  State<_Code> createState() => _CodeState();
}

class _CodeState extends State<_Code> {
  var copied = false;

  List<TextSpan> spans(List<hl.Node> nodes, Map<String, TextStyle> theme) => [
    for (final n in nodes)
      TextSpan(text: n.value, style: theme[n.className], children: n.children == null ? null : spans(n.children!, theme)),
  ];

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final theme = Theme.of(context).brightness == Brightness.dark ? atomOneDarkTheme : githubTheme;
    // an unknown or missing language stays plain
    final colored = widget.lang.isEmpty
        ? null
        : (() {
            try {
              return hl.highlight.parse(widget.code, language: widget.lang).nodes;
            } catch (_) {
              return null;
            }
          })();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.lang, style: TextStyle(fontSize: 12, color: c.outline)),
              ),
              Hover(
                radius: 8,
                label: AppLocalizations.of(context).a11yCopy,
                child: CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.zero,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: widget.code));
                    settings.haptic();
                    setState(() => copied = true);
                    await Future<void>.delayed(const Duration(seconds: 2));
                    if (mounted) setState(() => copied = false);
                  },
                  child: Icon(copied ? CupertinoIcons.checkmark_alt : CupertinoIcons.doc_on_doc, size: 16, color: c.outline),
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: SelectableText.rich(
            TextSpan(
              style: widget.mono,
              text: colored == null ? widget.code : null,
              children: colored == null ? null : spans(colored, theme),
            ),
          ),
        ),
      ],
    );
  }
}

/// [builder] told whether the mouse is over it.
class _Hovered extends StatefulWidget {
  const _Hovered({required this.builder});
  final Widget Function(bool hovered) builder;

  @override
  State<_Hovered> createState() => _HoveredState();
}

class _HoveredState extends State<_Hovered> {
  var on = false;

  @override
  Widget build(BuildContext context) =>
      MouseRegion(onEnter: (_) => setState(() => on = true), onExit: (_) => setState(() => on = false), child: widget.builder(on));
}

/// What Hermes asks the user in a reply: its `clarify` questions (picked among its choices or typed),
/// or a `sudo` password or a `secret` it needs. [onAnswer] gets the result the server request expects.
class _Ask extends StatefulWidget {
  const _Ask(this.ask, {super.key, required this.onAnswer, required this.choice});
  final ({Object id, String kind, Map params}) ask;
  final ValueChanged<Map<String, Object?>> onAnswer;
  final Widget Function(String label, VoidCallback onTap, bool main, bool danger) choice;

  @override
  State<_Ask> createState() => _AskState();
}

class _AskState extends State<_Ask> {
  late final questions = [
    for (final q in (widget.ask.params['questions'] as List? ?? const []).whereType<Map>())
      (
        id: '${q['qid']}',
        text: '${q['question'] ?? ''}',
        choices: [for (final c in q['choices'] as List? ?? const []) '$c'],
        multi: q['multi_select'] == true,
      ),
  ];
  late final picked = {for (final q in questions) q.id: <String>{}};
  late final typed = {for (final q in questions) q.id: TextEditingController()};
  final value = TextEditingController();

  @override
  void dispose() {
    for (final t in typed.values) {
      t.dispose();
    }
    value.dispose();
    super.dispose();
  }

  /// Each question's answer: what was typed, else the choice (a list when several may be picked); null = skipped.
  Map<String, Object?> get answers => {
    for (final q in questions)
      q.id: switch ((typed[q.id]!.text.trim(), picked[q.id]!)) {
        (final t, _) when t.isNotEmpty => q.multi ? [...picked[q.id]!, t] : t,
        (_, final p) when p.isEmpty => null,
        (_, final p) => q.multi ? [...p] : p.first,
      },
  };

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme, l = AppLocalizations.of(context);
    final p = widget.ask.params, secret = widget.ask.kind != 'clarify';
    final title = switch (widget.ask.kind) {
      'sudo' => l.askSudo,
      'secret' => '${p['prompt'] ?? ''}'.trim().isNotEmpty ? '${p['prompt']}'.trim() : l.askSecret,
      _ => l.askClarify,
    };
    final detail = switch (widget.ask.kind) {
      'sudo' => '${p['command'] ?? ''}'.trim(),
      'secret' => '${p['env_var'] ?? ''}'.trim(),
      _ => '',
    };
    Widget field(TextEditingController t, String hint, {bool hidden = false}) => Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10)),
      child: TextField(
        controller: t,
        obscureText: hidden,
        autofocus: hidden,
        autocorrect: !hidden,
        enableSuggestions: !hidden,
        onChanged: (_) => setState(() {}),
        onSubmitted: hidden ? (v) => widget.onAnswer({'value': v}) : null,
        style: TextStyle(fontSize: 15, color: c.onSurface),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: c.outline),
        ),
      ),
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onSurface),
          ),
          if (detail.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10)),
              child: SelectableText(
                detail,
                style: TextStyle(fontFamily: 'Menlo', fontSize: 13, color: c.onSurface),
              ),
            ),
          if (secret) field(value, widget.ask.kind == 'sudo' ? l.askPassword : l.askValue, hidden: true),
          for (final q in questions) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(q.text, style: TextStyle(fontSize: 15, color: c.onSurface)),
            ),
            if (q.choices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in q.choices)
                      widget.choice(
                        k,
                        () {
                          settings.haptic();
                          setState(() {
                            final p = picked[q.id]!;
                            if (q.multi) {
                              p.contains(k) ? p.remove(k) : p.add(k);
                            } else {
                              p.contains(k)
                                  ? p.clear()
                                  : (p
                                      ..clear()
                                      ..add(k));
                              typed[q.id]!.clear();
                            }
                          });
                        },
                        picked[q.id]!.contains(k),
                        false,
                      ),
                  ],
                ),
              ),
            field(typed[q.id]!, q.choices.isEmpty ? l.askAnswer : l.askOther),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              widget.choice(l.askSend, () => widget.onAnswer(secret ? {'value': value.text} : {'answers': answers}), true, false),
              // an empty value tells the server the user declined; `{}` skips every question
              widget.choice(secret ? l.approveDeny : l.askSkip, () => widget.onAnswer(secret ? {'value': ''} : {}), false, true),
            ],
          ),
        ],
      ),
    );
  }
}
