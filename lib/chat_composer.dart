part of 'chat_page.dart';

/// The composer: the field, its attachments, slash list, folder and send controls.
extension _Composer on _ChatPageState {
  Widget _composer(ColorScheme c) {
    final hasText = input.text.trim().isNotEmpty || pending.isNotEmpty;
    // the banner, attachments and skills above the field slide in rather than jump
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (slashes.isNotEmpty) _slashList(c),
          if (editing case final m? when !streaming && chat.msgs.contains(m))
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 6, 16, 0),
              child: Row(
                children: [
                  Icon(CupertinoIcons.pencil, size: 16, color: c.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(AppLocalizations.of(context).editingMessage, style: TextStyle(fontSize: 13, color: c.outline)),
                  ),
                  GestureDetector(
                    onTap: cancelEdit,
                    child: Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: c.outline),
                  ),
                ],
              ),
            ),
          if (pending.isNotEmpty)
            SizedBox(
              height: 76,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                children: [
                  for (final f in pending)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Attachment(f, onRemove: () => setState(() => pending.remove(f))),
                    ),
                ],
              ),
            ),
          _composerRow(c, hasText),
          if (const [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux].contains(defaultTargetPlatform)) _folderChip(c),
        ],
      ),
    );
  }

  /// The folder the chat works in, under the composer; it changes between turns.
  Widget _folderChip(ColorScheme c) {
    final l = AppLocalizations.of(context);
    final busy = streaming || chat.shell.busy;
    final home = MacShell.home;
    final path = chat.folderHere && (chat.folder == home || chat.folder.startsWith('$home/'))
        ? '~${chat.folder.substring(home.length)}'
        : chat.folder;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(58, 0, 12, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: _folderButton(c, busy, path)),
            // what the bot changed there (no folder picked: the server's default one)
            Hover(
              radius: 8,
              child: GestureDetector(
                onTap: () => show(GitPage(path: chat.folder, here: chat.folderHere)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.arrow_branch, size: 14, color: c.outline),
                      const SizedBox(width: 4),
                      Text(l.gitTitle, style: TextStyle(fontSize: 13, color: c.outline)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _folderButton(ColorScheme c, bool busy, String path) {
    final l = AppLocalizations.of(context);
    return Opacity(
      opacity: busy ? .5 : 1,
      child: Hover(
        radius: 8,
        child: GestureDetector(
          onTap: busy ? null : pickFolder,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(chat.folderHere ? CupertinoIcons.desktopcomputer : CupertinoIcons.folder, size: 14, color: c.outline),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    path.isEmpty ? l.folder : '$path · ${chat.folderHere ? l.folderOnHere : l.folderOnServer}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.outline),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(CupertinoIcons.chevron_down, size: 10, color: c.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The skills matching what's typed, above the composer.
  Widget _slashList(ColorScheme c) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
    constraints: const BoxConstraints(maxHeight: 260),
    decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final s in slashes)
          Hover(
            radius: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => pickSlash(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.display.startsWith('/') ? s.display : '/${s.display}',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onSurface),
                    ),
                    if (s.meta.isNotEmpty)
                      Text(
                        s.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.outline),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _composerRow(ColorScheme c, bool hasText) {
    final stopping = streaming && !hasText; // the button stops the reply; with text, it queues it
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Hover(
            radius: 999,
            child: GestureDetector(
              onTap: attachFiles, // mid-reply too, for the queued message
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.surfaceContainerHighest, shape: BoxShape.circle),
                child: Icon(CupertinoIcons.add, size: 22, color: c.onSurface),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListenableBuilder(
              listenable: focus,
              builder: (context, child) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.only(left: 16, right: 4),
                decoration: BoxDecoration(
                  color: c.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: focus.hasFocus ? c.onSurface.withValues(alpha: .12) : Colors.transparent,
                    strokeAlign: BorderSide.strokeAlignOutside, // no layout shift
                  ),
                ),
                child: child,
              ),
              child: Builder(
                builder: (context) {
                  final style = TextStyle(fontSize: 17, color: c.onSurface);
                  // the ring fades away while typing; nothing to measure before the first message
                  final showRing = chat.msgs.isNotEmpty && input.text.isEmpty;
                  final sendBtn = ListenableBuilder(
                    listenable: voice,
                    builder: (context, _) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: ScaleTransition(scale: a, child: child),
                      ),
                      // nothing typed: the microphone (Linux has no system speech recognition)
                      child: voice.listening || (!hasText && !streaming)
                          ? Platform.isLinux
                                ? const SizedBox(height: 44)
                                : Hover(
                                    key: ValueKey('mic${voice.listening}'),
                                    radius: 999,
                                    child: GestureDetector(
                                      onTap: dictate,
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        margin: const EdgeInsets.symmetric(vertical: 4),
                                        decoration: BoxDecoration(
                                          color: voice.listening ? const Color(0xFFFF3B30) : Colors.transparent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          voice.listening ? CupertinoIcons.mic_fill : CupertinoIcons.mic,
                                          size: 20,
                                          color: voice.listening ? Colors.white : c.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  )
                          : Hover(
                              key: ValueKey(stopping),
                              radius: 999,
                              child: GestureDetector(
                                onTap: stopping ? stop : send,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                                  child: stopping
                                      ? Center(
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(color: c.onPrimary, borderRadius: BorderRadius.circular(2)),
                                          ),
                                        )
                                      : Icon(CupertinoIcons.arrow_up, size: 20, color: c.onPrimary),
                                ),
                              ),
                            ),
                    ),
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        // centered in 44 pt while single-line, grows afterwards
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          alignment: Alignment.centerLeft,
                          child: TextField(
                            controller: input,
                            focusNode: focus,
                            minLines: 1,
                            maxLines: 6,
                            textCapitalization: TextCapitalization.sentences,
                            style: style,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              hintText: streaming
                                  ? AppLocalizations.of(context).composerQueueHint
                                  : AppLocalizations.of(context).composerHint,
                              hintStyle: TextStyle(fontSize: 17, color: c.outline),
                            ),
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SizeTransition(sizeFactor: a, axis: Axis.horizontal, axisAlignment: -1, child: child),
                        ),
                        child: showRing
                            ? Padding(
                                key: const ValueKey('ring'),
                                padding: const EdgeInsets.only(left: 8, right: 12, bottom: 12),
                                child: _ContextRing(
                                  chat.context ?? contextUse([for (final m in chat.msgs) m.text].join()),
                                  cost: chat.cost,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      sendBtn,
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The results the app handed Hermes for the steps a reply asked: one line, opened to read them.
/// The folders of this computer or of the server, browsed from [folder]; pops the one picked, and where.
class _Folders extends StatefulWidget {
  const _Folders({required this.folder, required this.here, required this.server});
  final String folder;
  final bool here;
  final Future<List<String>> Function(String path) server;

  @override
  State<_Folders> createState() => _FoldersState();
}

class _FoldersState extends State<_Folders> {
  late var here = widget.here;
  // what is typed on each side: a folder ending in '/', then the start of a name to narrow its list
  late final paths = {
    true: TextEditingController(text: widget.here && widget.folder.isNotEmpty ? '${tilde(widget.folder)}/' : '~/'),
    false: TextEditingController(text: !widget.here && widget.folder.isNotEmpty ? '${widget.folder}/' : '~/'),
  };
  TextEditingController get path => paths[here]!;
  List<String>? dirs; // null while listed
  String? listed;

  static String tilde(String p) {
    final home = MacShell.home;
    return p == home || p.startsWith('$home/') ? '~${p.substring(home.length)}' : p;
  }

  /// This computer's folders in what [path] names, those starting with its last part.
  static Future<List<String>> local(String path) async {
    final at = path.lastIndexOf('/') + 1;
    final dir = path.substring(0, at).replaceFirst(RegExp(r'^~(?=/)'), MacShell.home);
    final start = path.substring(at).toLowerCase();
    return [
      await for (final e in Directory(dir.isEmpty ? '.' : dir).list().handleError((Object _) {}))
        if (e is Directory && e.path.split('/').last.toLowerCase().startsWith(start)) e.path.split('/').last,
    ];
  }

  @override
  void initState() {
    super.initState();
    for (final p in paths.values) {
      p.addListener(load);
    }
    load();
  }

  @override
  void dispose() {
    for (final p in paths.values) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    final key = '$here${path.text}';
    if (key == listed) return;
    listed = key;
    if (dirs != null) setState(() => dirs = null);
    final t = path.text;
    final found = await (here ? local(t) : widget.server(t)).catchError((Object _) => <String>[]);
    found.sort(
      (a, b) => a.startsWith('.') == b.startsWith('.') ? a.toLowerCase().compareTo(b.toLowerCase()) : (a.startsWith('.') ? 1 : -1),
    );
    if (mounted && listed == key) setState(() => dirs = found);
  }

  String get base => path.text.substring(0, path.text.lastIndexOf('/') + 1); // the folder listed

  void go(String to) => path.value = TextEditingValue(
    text: to,
    selection: TextSelection.collapsed(offset: to.length),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Theme.of(context).colorScheme;
    final parent = switch (base.isEmpty ? '' : base.substring(0, base.length - 1)) {
      '' => null, // at the root
      '~' => here ? '${tilde(Directory(MacShell.home).parent.path)}/' : '/',
      final b => b.substring(0, b.lastIndexOf('/') + 1),
    };
    final t = path.text;
    final shown = t.length > 1 && t.endsWith('/') ? t.substring(0, t.length - 1) : t;
    final picked = here ? shown.replaceFirst(RegExp(r'^~(?=/|$)'), MacShell.home) : shown;
    void choose() => picked.isEmpty ? null : Navigator.pop(context, (picked, here));
    final bold = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface);
    return Material(
      color: c.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              width: double.infinity, // a column's child is only as wide as its title, the buttons over it
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(l.folderTitle, style: bold),
                  Positioned(
                    left: 4,
                    child: Hover(
                      radius: 8,
                      child: CupertinoButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l.cancel, style: TextStyle(fontSize: 17, color: c.onSurface)),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    child: Hover(
                      radius: 8,
                      child: CupertinoButton(
                        onPressed: picked.isEmpty ? null : choose,
                        child: Text(l.folderChoose, style: bold.copyWith(color: picked.isEmpty ? c.outline : null)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (macCapable)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<bool>(
                    groupValue: here,
                    thumbColor: c.surface,
                    backgroundColor: c.surfaceContainerHighest,
                    onValueChanged: (v) {
                      setState(() => here = v!);
                      load();
                    },
                    children: {
                      for (final (v, name) in [(true, l.folderHere), (false, l.folderServer)])
                        v: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(name, style: TextStyle(fontSize: 15, color: c.onSurface)),
                        ),
                    },
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  Hover(
                    radius: 8,
                    child: GestureDetector(
                      onTap: parent == null ? null : () => go(parent),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(CupertinoIcons.arrow_up, size: 18, color: parent == null ? c.outlineVariant : c.onSurface),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: CupertinoTextField(
                      key: ValueKey(here),
                      controller: path,
                      autofocus: true,
                      autocorrect: false,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      style: TextStyle(fontSize: 15, color: c.onSurface),
                      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                      onSubmitted: (_) => choose(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (dirs) {
                null => const Center(child: CupertinoActivityIndicator()),
                final dirs => ListView(
                  children: [
                    CupertinoListSection.insetGrouped(
                      backgroundColor: c.surface,
                      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                      separatorColor: c.outline.withValues(alpha: .2),
                      footer: Text(here ? l.folderHereHint : l.folderServerHint, style: TextStyle(fontSize: 13, color: c.outline)),
                      children: [
                        if (dirs.isEmpty)
                          CupertinoListTile(
                            title: Text(l.folderEmpty, style: TextStyle(fontSize: 15, color: c.outline)),
                          ),
                        for (final d in dirs)
                          Hover(
                            radius: 0,
                            child: CupertinoListTile(
                              leading: Icon(CupertinoIcons.folder, size: 20, color: c.outline),
                              title: Text(d, style: TextStyle(fontSize: 17, color: c.onSurface)),
                              trailing: const CupertinoListTileChevron(),
                              onTap: () => go('$base$d/'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// How full the context window is, as a ring; tap for the percentage.
class _ContextRing extends StatelessWidget {
  const _ContextRing(this.used, {this.cost = 0});
  final double used, cost;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Theme.of(context).colorScheme;
    return Tooltip(
      message: [
        l.contextUsage((used * 100).round()),
        if (cost > 0) l.chatCost(NumberFormat.simpleCurrency(locale: '${Localizations.localeOf(context)}', name: 'USD').format(cost)),
      ].join('\n'),
      triggerMode: TooltipTriggerMode.tap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: used),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        builder: (context, v, _) => SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            value: v,
            strokeWidth: 2.5,
            strokeCap: StrokeCap.round,
            backgroundColor: c.outline.withValues(alpha: .25),
            color: v > .9 ? Colors.red : c.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
