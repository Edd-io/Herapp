part of 'chat_page.dart';

/// The menu: the conversations, their search and the pages.
extension _Sidebar on _ChatPageState {
  /// Searches the conversations' content for [q] once typing pauses.
  Future<void> search(String q) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (q != query || !mounted) return;
    if (q.trim().length < 2) return setState(() => found = []);
    try {
      final body = await serverApi('GET', '/api/sessions/search', query: {'q': q.trim(), 'limit': '20'});
      if (mounted && q == query) setState(() => found = body == null ? [] : parseFound(body));
    } catch (e) {
      debugPrint('Search: $e');
    }
  }

  void openFound(Found f) {
    final known = [...chats, ?bot].where((ch) => ch.stored == f.id).firstOrNull;
    if (known == null) setState(() => chats.add(Chat(stored: f.id, name: f.title)));
    select(known ?? chats.last);
  }

  Widget _sidebar(ColorScheme c) {
    final q = query.toLowerCase();
    final listed = chats.where((ch) => ch.title.isNotEmpty && ch.title.toLowerCase().contains(q));
    // the others by last activity, under Today, Yesterday… (a chat started here is active now)
    final now = DateTime.now();
    final recent = [...listed.where((ch) => !ch.pinned)]..sort((a, b) => (b.active ?? now).compareTo(a.active ?? now));
    int group(Chat ch) => dayGroup(ch.active ?? now, now);
    Widget tile(
      String label, {
      IconData? icon,
      bool selected = false,
      bool busy = false, // the bot answers there
      required VoidCallback onTap,
      VoidCallback? onMenu,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Hover(
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onMenu,
          onSecondaryTap: onMenu,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: !selected
                  ? Colors.transparent
                  : settings.accent == 0
                  ? c.surfaceContainerHighest
                  : c.primary.withValues(alpha: .3),
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
                if (busy) ...[const SizedBox(width: 8), _PulseDot(CupertinoColors.systemGreen.resolveFrom(context), size: 8)],
              ],
            ),
          ),
        ),
      ),
    );
    Widget dayHeading(int group) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: Text(
        [l.chatsToday, l.chatsYesterday, l.chatsWeek, l.chatsMonth, l.chatsOlder][group],
        style: TextStyle(fontSize: 12, color: c.outline),
      ),
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.outline),
      ),
    );
    // swipe left to delete, right to archive, as in iOS lists; held (or right-clicked) for the menu
    Widget listedTile(Chat ch) => Dismissible(
      key: ObjectKey(ch),
      direction: ch.stored.isEmpty ? DismissDirection.endToStart : DismissDirection.horizontal,
      confirmDismiss: (d) => d == DismissDirection.endToStart ? confirmDelete(ch) : archive(ch.stored),
      onDismissed: (_) => deleted(ch),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        color: CupertinoColors.systemIndigo.darkColor,
        child: const Icon(CupertinoIcons.archivebox, color: CupertinoColors.white, size: 20),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: const Color(0xFF9E1B1B), // darker than systemRed
        child: const Icon(CupertinoIcons.trash, color: CupertinoColors.white, size: 20),
      ),
      child: tile(
        ch.title,
        icon: ch.pinned ? CupertinoIcons.pin : null,
        selected: identical(ch, chat),
        busy: ch.streaming || ch.tasks.isNotEmpty,
        onTap: () => select(ch),
        onMenu: ch.stored.isEmpty ? null : () => chatMenu(ch),
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
                        focusNode: searchFocus,
                        onChanged: (v) {
                          setState(() => query = v);
                          search(v);
                        },
                        style: TextStyle(fontSize: 16, color: c.onSurface),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          hintText: AppLocalizations.of(context).search,
                          hintStyle: TextStyle(fontSize: 16, color: c.outline),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // the menu scrolls away with the chats
                  // a full-width button, centered over the grid below
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                    child: Hover(
                      radius: 12,
                      child: GestureDetector(
                        onTap: newChat,
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: settings.accent == 0 ? c.surfaceContainerHighest : c.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(CupertinoIcons.square_pencil, size: 17, color: settings.accent == 0 ? c.onSurface : c.onPrimary),
                              const SizedBox(width: 10),
                              Text(
                                l.newChat,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: settings.accent == 0 ? c.onSurface : c.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // the pages, settings last, in a compact grid that leaves the room to the chats
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: LayoutBuilder(
                      builder: (context, box) => Wrap(
                        children: [
                          for (final (label, icon, onTap) in [
                            for (final (label, icon, page) in pages(l)) (label, icon, () => openPage(page)),
                            (l.settings, CupertinoIcons.gear, openSettings),
                          ])
                            SizedBox(
                              width: box.maxWidth / 4,
                              child: Hover(
                                label: label,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: onTap,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Column(
                                      children: [
                                        Icon(icon, size: 22, color: c.onSurface),
                                        const SizedBox(height: 4),
                                        Text(
                                          label,
                                          maxLines: 2,
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 11, height: 1.15, color: c.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Divider(height: 1, thickness: .5, color: c.outline.withValues(alpha: .3)),
                  ),
                  if (listed.any((ch) => ch.pinned)) ...[
                    heading(l.chatsPinned),
                    for (final ch in listed.where((ch) => ch.pinned)) listedTile(ch),
                  ],
                  heading(l.chats),
                  if (bot case final b? when b.name.toLowerCase().contains(q))
                    tile(
                      b.name,
                      icon: CupertinoIcons.bubble_left_bubble_right,
                      selected: identical(b, chat),
                      onTap: () => select(b),
                      // held (or right-clicked): cleared, the only thing done to it
                      onMenu: clearBot,
                    ),
                  for (final (i, ch) in recent.indexed) ...[
                    if (i == 0 || group(ch) != group(recent[i - 1])) dayHeading(group(ch)),
                    listedTile(ch),
                  ],
                  if (q.isEmpty) tile(l.chatsArchived, icon: CupertinoIcons.archivebox, onTap: () => show(_Archived(this))),
                  if (found.where((f) => query.trim().length >= 2 && !listed.any((ch) => ch.stored == f.id)).toList() case final more
                      when more.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
                      child: Text(
                        AppLocalizations.of(context).searchInMessages,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.outline),
                      ),
                    ),
                    for (final f in more)
                      Hover(
                        radius: 8,
                        child: GestureDetector(
                          onTap: () => openFound(f),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 16, color: c.onSurface),
                                ),
                                const SizedBox(height: 2),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      // the server marks the hits >>>like this<<<
                                      for (final (i, part) in f.snippet.split(RegExp('>>>|<<<')).indexed)
                                        TextSpan(
                                          text: part,
                                          style: i.isOdd ? TextStyle(fontWeight: FontWeight.w600, color: c.onSurface) : null,
                                        ),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: c.outline),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// The archived conversations: one opens, or comes back to the menu.
class _Archived extends StatefulWidget {
  const _Archived(this.page);
  final _ChatPageState page;

  @override
  State<_Archived> createState() => _ArchivedState();
}

class _ArchivedState extends State<_Archived> {
  List<Session>? rows;
  Object? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final body = await serverApi('GET', '/api/sessions', query: {'archived': 'only', 'limit': '100', 'order': 'recent'});
      if (mounted) setState(() => rows = parseSessions(jsonDecode(body ?? '{}') as Map));
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> unarchive(Session s) async {
    if (!await widget.page.archive(s.id, on: false)) return;
    setState(() => rows!.remove(s));
    widget.page.loadSessions();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return PageFrame(
      title: l.chatsArchived,
      child: switch (rows) {
        null when error != null => Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            serverErrorText(l, error),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.outline),
          ),
        ),
        null => const Center(child: CupertinoActivityIndicator()),
        [] => Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l.archivedNone,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.outline),
          ),
        ),
        final rows => ListView(
          children: [
            for (final s in rows)
              CupertinoListTile(
                title: Text(s.title, style: TextStyle(fontSize: 16, color: c.onSurface)),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.page.openFound((id: s.id, title: s.title, snippet: ''));
                },
                trailing: CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: () => unarchive(s),
                  child: Text(l.chatUnarchive, style: const TextStyle(fontSize: 15)),
                ),
              ),
          ],
        ),
      },
    );
  }
}
