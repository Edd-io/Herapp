import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'hermes.dart';
import 'settings.dart';

class Chat {
  final msgs = <Msg>[];
  String model = settings.model;
  String get title => msgs.isEmpty ? 'Nouveau chat' : msgs.first.text;
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with SingleTickerProviderStateMixin {
  final chats = [Chat()];
  late Chat chat = chats.first;
  final input = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  late final drawer = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  StreamSubscription<String>? sub;
  Msg? fresh; // dernier message utilisateur, animé à l'arrivée
  bool atBottom = true;
  String query = '';

  bool get streaming => sub != null;

  @override
  void initState() {
    super.initState();
    input.addListener(() => setState(() {}));
    scroll.addListener(() {
      final b = scroll.position.extentAfter < 40;
      if (b != atBottom) setState(() => atBottom = b);
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    drawer.dispose();
    input.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  void send() {
    final text = input.text.trim();
    if (text.isEmpty || streaming) return;
    settings.haptic();
    input.clear();
    final m = Msg(true, text);
    setState(() {
      chat.msgs.add(m);
      fresh = m;
    });
    respond();
  }

  void respond() {
    final reply = Msg(false, '');
    final history = List.of(chat.msgs);
    setState(() => chat.msgs.add(reply));
    toBottom();
    sub = hermes(history, chat.model).listen(
      (chunk) {
        setState(() => reply.text += chunk);
        if (atBottom) toBottom(jump: true);
      },
      onDone: stop,
      onError: (Object e) {
        reply.text += '\n\n⚠️ $e';
        stop();
      },
    );
  }

  void stop() {
    sub?.cancel();
    if (chat.msgs.isNotEmpty && !chat.msgs.last.user && chat.msgs.last.text.isEmpty) chat.msgs.removeLast();
    setState(() => sub = null);
  }

  void regenerate() {
    stop();
    setState(() => chat.msgs.removeLast());
    respond();
  }

  void newChat() {
    stop();
    if (chat.msgs.isNotEmpty) chats.insert(0, chat = Chat());
    setState(() {});
    closeDrawer();
  }

  void select(Chat c) {
    stop();
    setState(() => chat = c);
    closeDrawer();
    toBottom(jump: true);
  }

  /// Feuille de choix du modèle, groupée par fournisseur.
  Future<void> pickModel() async {
    final c = Theme.of(context).colorScheme;
    final current = modelOf(chat.model).id;
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: c.surface,
      barrierColor: Colors.black.withValues(alpha: .4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => _ModelSheet(current: current),
    );
    if (id == null || !mounted) return;
    settings.haptic();
    setState(() => chat.model = settings.model = id);
  }

  void openDrawer() {
    focus.unfocus();
    drawer.animateTo(1, curve: Curves.easeOutCubic);
  }

  void closeDrawer() => drawer.animateTo(0, curve: Curves.easeOutCubic);

  void toBottom({bool jump = false}) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!scroll.hasClients) return;
    final max = scroll.position.maxScrollExtent;
    jump ? scroll.jumpTo(max) : scroll.animateTo(max, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context).width;
    final width = screen * .82;
    final main = _main(c);
    final sidebar = _sidebar(c);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.surfaceContainerLow,
        body: GestureDetector(
          onHorizontalDragStart: (_) => focus.unfocus(),
          onHorizontalDragUpdate: (d) => drawer.value += d.primaryDelta! / width,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            (v.abs() > 300 ? v > 0 : drawer.value > .5) ? openDrawer() : closeDrawer();
          },
          child: AnimatedBuilder(
            animation: drawer,
            builder: (context, _) {
              final x = drawer.value * width;
              return Stack(
                children: [
                  Positioned(left: x - width, top: 0, bottom: 0, width: width, child: sidebar),
                  Positioned(
                    left: x,
                    top: 0,
                    bottom: 0,
                    width: screen,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        main,
                        if (drawer.value > 0)
                          GestureDetector(
                            onTap: closeDrawer,
                            child: ColoredBox(color: Colors.black.withValues(alpha: .25 * drawer.value)),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _main(ColorScheme c) => ColoredBox(
    color: c.surface,
    child: SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 52,
            child: Row(
              children: [
                _IconBtn(onTap: openDrawer, child: _MenuIcon(c.onSurface)),
                Expanded(
                  // vide : pas de titre, la pastille au centre sert de sélecteur
                  child: chat.msgs.isEmpty
                      ? const SizedBox()
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Hermes',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                modelOf(chat.model).name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 17, color: c.outline),
                              ),
                            ),
                          ],
                        ),
                ),
                _IconBtn(
                  onTap: newChat,
                  child: Icon(CupertinoIcons.square_pencil, size: 24, color: c.onSurface),
                ),
              ],
            ),
          ),
          Expanded(
            child: chat.msgs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Par quoi commençons-nous ?',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: c.onSurface),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: pickModel,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  modelOf(chat.model).name,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.onSurface),
                                ),
                                const SizedBox(width: 6),
                                Text(modelOf(chat.model).provider, style: TextStyle(fontSize: 15, color: c.outline)),
                                const SizedBox(width: 6),
                                Icon(CupertinoIcons.chevron_down, size: 13, color: c.outline),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        controller: scroll,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: chat.msgs.length,
                        itemBuilder: (_, i) => _message(c, chat.msgs[i], i == chat.msgs.length - 1),
                      ),
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: AnimatedScale(
                            scale: atBottom ? 0 : 1,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutBack,
                            child: GestureDetector(
                              onTap: toBottom,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: c.surfaceContainerHighest),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 8, offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: Icon(CupertinoIcons.arrow_down, size: 18, color: c.onSurface),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          _composer(c),
        ],
      ),
    ),
  );

  Widget _message(ColorScheme c, Msg m, bool last) {
    const body = TextStyle(fontSize: 17, height: 1.45);
    if (m.user) {
      final bubble = Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 64, top: 12, bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(22)),
          child: Text(m.text, style: body.copyWith(color: c.onSurface)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.text.isEmpty) _PulseDot(c.onSurface) else _StreamText(m.text, style: body.copyWith(color: c.onSurface)),
          if (!live && m.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  _IconBtn(
                    small: true,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: m.text.trim()));
                      settings.haptic();
                    },
                    child: Icon(CupertinoIcons.doc_on_doc, size: 18, color: c.onSurfaceVariant),
                  ),
                  if (last)
                    _IconBtn(
                      small: true,
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

  Widget _composer(ColorScheme c) {
    final hasText = input.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: c.surfaceContainerHighest, shape: BoxShape.circle),
            child: Icon(CupertinoIcons.add, size: 22, color: c.onSurface),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(left: 16, right: 4),
              decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(22)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    // centré dans 44 pt quand il n'y a qu'une ligne, grandit ensuite
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.centerLeft,
                      child: TextField(
                        controller: input,
                        focusNode: focus,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(fontSize: 17, color: c.onSurface),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          hintText: 'Poser une question',
                          hintStyle: TextStyle(fontSize: 17, color: c.outline),
                        ),
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: !hasText && !streaming
                        ? const SizedBox(width: 12, height: 44)
                        : GestureDetector(
                            key: ValueKey(streaming),
                            onTap: streaming ? stop : send,
                            child: Container(
                              width: 36,
                              height: 36,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                              child: streaming
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebar(ColorScheme c) {
    final q = query.toLowerCase();
    final listed = chats.where((ch) => ch.msgs.isNotEmpty && ch.title.toLowerCase().contains(q));
    Widget tile(String label, {IconData? icon, bool selected = false, required VoidCallback onTap}) => GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? c.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (icon != null) ...[Icon(icon, size: 20, color: c.onSurface), const SizedBox(width: 12)],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: c.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
    return ColoredBox(
      color: c.surfaceContainerLow,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.search, size: 18, color: c.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => query = v),
                        style: TextStyle(fontSize: 16, color: c.onSurface),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          hintText: 'Rechercher',
                          hintStyle: TextStyle(fontSize: 16, color: c.outline),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            tile('Nouveau chat', icon: CupertinoIcons.square_pencil, onTap: newChat),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: Text(
                'Chats',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.outline),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [for (final ch in listed) tile(ch.title, selected: identical(ch, chat), onTap: () => select(ch))],
              ),
            ),
            tile(
              'Paramètres',
              icon: CupertinoIcons.gear,
              onTap: () => showCupertinoSheet(context: context, builder: (_) => const SettingsSheet()),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.onTap, required this.child, this.small = false});
  final VoidCallback onTap;
  final Widget child;
  final bool small;

  @override
  Widget build(BuildContext context) => CupertinoButton(padding: EdgeInsets.all(small ? 6 : 14), onPressed: onTap, child: child);
}

/// Icône menu à deux traits inégaux.
class _MenuIcon extends StatelessWidget {
  const _MenuIcon(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w) => Container(
      width: w,
      height: 2,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
    );
    return SizedBox(
      width: 24,
      height: 24,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bar(20), const SizedBox(height: 6), bar(13)],
      ),
    );
  }
}

/// Point pulsant affiché en attendant le premier morceau de réponse.
class _PulseDot extends StatefulWidget {
  const _PulseDot(this.color);
  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final a = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

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
        width: 13,
        height: 13,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    ),
  );
}

/// Texte dont chaque morceau ajouté apparaît en fondu.
class _StreamText extends StatefulWidget {
  const _StreamText(this.text, {required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_StreamText> createState() => _StreamTextState();
}

class _StreamTextState extends State<_StreamText> with SingleTickerProviderStateMixin {
  static const fade = Duration(milliseconds: 350);
  final marks = <(int, Duration)>[]; // (début du morceau, instant d'arrivée)
  Duration now = Duration.zero;
  Ticker? ticker; // créé seulement si le texte grandit

  void _tick(Duration elapsed) {
    setState(() {
      now = elapsed;
      marks.removeWhere((m) => now - m.$2 >= fade);
    });
    if (marks.isEmpty) ticker!.stop();
  }

  @override
  void didUpdateWidget(_StreamText old) {
    super.didUpdateWidget(old);
    if (widget.text.length <= old.text.length || !widget.text.startsWith(old.text)) return;
    final tk = ticker ??= createTicker(_tick);
    if (!tk.isActive) {
      now = Duration.zero;
      tk.start();
    }
    marks.add((old.text.length, now));
  }

  @override
  void dispose() {
    ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.text;
    if (marks.isEmpty) return Text(t, style: widget.style);
    final color = widget.style.color!;
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          TextSpan(text: t.substring(0, marks.first.$1)),
          for (var i = 0; i < marks.length; i++)
            TextSpan(
              text: t.substring(marks[i].$1, i + 1 < marks.length ? marks[i + 1].$1 : t.length),
              style: TextStyle(color: color.withValues(alpha: ((now - marks[i].$2).inMicroseconds / fade.inMicroseconds).clamp(0, 1))),
            ),
        ],
      ),
    );
  }
}

class _ModelSheet extends StatelessWidget {
  const _ModelSheet({required this.current});
  final String current;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final providers = {for (final m in models) m.provider};
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Modèle',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                for (final p in providers) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: c.onSurface,
                          child: Text(
                            p[0],
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.surface),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          p,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.outline),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        for (final (i, m) in models.where((m) => m.provider == p).indexed) ...[
                          if (i > 0) Divider(height: 1, indent: 16, color: c.outline.withValues(alpha: .15)),
                          _ModelRow(m, selected: m.id == current),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow(this.m, {required this.selected});
  final Model m;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.of(context).pop(m.id),
      highlightColor: c.onSurface.withValues(alpha: .06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.name,
                    style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: c.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(m.desc, style: TextStyle(fontSize: 13, color: c.outline)),
                ],
              ),
            ),
            AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                child: Icon(CupertinoIcons.checkmark, size: 13, color: c.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
