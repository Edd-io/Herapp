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
    Widget tile(String label, {IconData? icon, bool selected = false, required VoidCallback onTap}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Hover(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
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
                  tile(AppLocalizations.of(context).newChat, icon: CupertinoIcons.square_pencil, onTap: newChat),
                  for (final (label, icon, page) in pages(AppLocalizations.of(context)))
                    tile(label, icon: icon, onTap: () => openPage(page)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
                    child: Text(
                      AppLocalizations.of(context).chats,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.outline),
                    ),
                  ),
                  if (bot case final b? when b.name.toLowerCase().contains(q))
                    tile(b.name, icon: CupertinoIcons.bubble_left_bubble_right, selected: identical(b, chat), onTap: () => select(b)),
                  for (final ch in listed)
                    // swipe left to delete, as in iOS lists
                    Dismissible(
                      key: ObjectKey(ch),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => confirmDelete(ch),
                      onDismissed: (_) => deleted(ch),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        color: const Color(0xFF9E1B1B), // darker than systemRed
                        child: const Icon(CupertinoIcons.trash, color: CupertinoColors.white, size: 20),
                      ),
                      child: tile(ch.title, selected: identical(ch, chat), onTap: () => select(ch)),
                    ),
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
            tile(AppLocalizations.of(context).settings, icon: CupertinoIcons.gear, onTap: openSettings),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
