part of 'chat_page.dart';

/// How a conversation shows: messages, tool calls, approvals and the cards a reply brings.
extension _Messages on _ChatPageState {
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                text,
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
                  ],
                ),
              ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.tools.isNotEmpty) _Tools(m.tools, live: live),
          // its browser runs on the bot's screen: watched as it goes, taken over for a CAPTCHA
          if (last && m.tools.any((t) => t.name.startsWith('browser') || t.name == 'computer_use'))
            _ScreenPreview(live: live, onOpen: () => show(const ScreenPage())),
          for (final t in m.tools.where((t) => t.done))
            if (memoryChanges(t) case final changes when changes.isNotEmpty) _memoryCard(c, changes),
          if (m.ask case final ask?) _approval(c, m, ask.params),
          if (text.trim().isNotEmpty)
            _Markdown(text.trimLeft(), style: body.copyWith(color: c.onSurface)) // text after a tool call starts with blank lines
          else if (live && m.ask == null && m.tools.every((t) => t.done))
            _PulseDot(c.onSurface),
          for (final (i, s) in steps.indexed) _macCard(c, s, m.mac.elementAtOrNull(i)),
          if (!live && m.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
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
        ],
      ),
    );
  }

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
      () => answer(m, k),
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

/// The tools a reply used: listed while it runs, folded into one line once it's done.
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
    final style = TextStyle(fontSize: 14, color: c.onSurfaceVariant);
    Widget row(Widget lead, Widget text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 18, child: Center(child: lead)),
          const SizedBox(width: 6),
          Expanded(child: text),
        ],
      ),
    );
    final rows = [
      for (final t in widget.tools)
        row(
          t.done ? Icon(CupertinoIcons.checkmark_alt, size: 14, color: c.onSurfaceVariant) : const CupertinoActivityIndicator(radius: 6),
          Text.rich(
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
    ];
    if (widget.live) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(children: rows),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
          Hover(
            radius: 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => open = !open),
              child: row(
                Icon(CupertinoIcons.wrench, size: 14, color: c.onSurfaceVariant),
                Row(
                  children: [
                    Text(AppLocalizations.of(context).toolsUsed(widget.tools.length), style: style),
                    Icon(open ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down, size: 13, color: c.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          if (open) ...rows,
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
