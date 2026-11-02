import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
import 'settings.dart';

/// Something the palette runs: a command, a page or a chat; [keys] is its shortcut as shown, [group] its section.
typedef PaletteItem = ({String label, IconData icon, String group, String keys, VoidCallback run});

/// [items] matching [query], those starting with it first, then the others containing it, each in their order.
List<PaletteItem> matching(List<PaletteItem> items, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  final words = q.split(RegExp(r'\s+'));
  final hits = items.where((i) => words.every(i.label.toLowerCase().contains)).toList();
  return [...hits.where((i) => i.label.toLowerCase().startsWith(q)), ...hits.where((i) => !i.label.toLowerCase().startsWith(q))];
}

/// The command palette (⌘K): typed to find a command, a page or a chat, run with Enter or a click.
/// [more] adds what the server finds for the query (chats whose messages match), once typing pauses.
Future<void> showPalette(BuildContext context, List<PaletteItem> items, {Future<List<PaletteItem>> Function(String query)? more}) =>
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: .3),
      transitionDuration: const Duration(milliseconds: 140),
      transitionBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: .98, end: 1.0).animate(a), child: child),
      ),
      pageBuilder: (_, _, _) => _Palette(items, more: more),
    );

class _Palette extends StatefulWidget {
  const _Palette(this.items, {this.more});
  final List<PaletteItem> items;
  final Future<List<PaletteItem>> Function(String query)? more;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final field = TextEditingController();
  final scroll = ScrollController();
  late final focus = FocusNode(onKeyEvent: key);
  var at = 0; // the highlighted row
  List<PaletteItem> found = []; // the server's, for the current query
  Timer? wait;

  List<PaletteItem> get shown => [...matching(widget.items, field.text), ...found];

  @override
  void dispose() {
    wait?.cancel();
    field.dispose();
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  void typed(String q) {
    setState(() {
      at = 0;
      found = [];
    });
    wait?.cancel();
    if (widget.more == null || q.trim().length < 2) return;
    wait = Timer(const Duration(milliseconds: 300), () async {
      final got = await widget.more!(q);
      if (mounted && field.text == q) setState(() => found = got);
    });
  }

  void run(PaletteItem i) {
    Navigator.pop(context);
    i.run();
  }

  /// Up and Down move the highlight, Enter runs it; Escape is the dialog's own.
  KeyEventResult key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final list = shown;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.arrowUp when list.isNotEmpty:
        setState(() => at = (at + (e.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1)) % list.length);
        // the highlighted row stays in view (rows are 44 high)
        if (scroll.hasClients) {
          final top = at * 44.0, view = scroll.position.viewportDimension;
          if (top < scroll.offset) scroll.jumpTo(top);
          if (top + 44 > scroll.offset + view) scroll.jumpTo(top + 44 - view);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter when list.isNotEmpty:
        run(list[at.clamp(0, list.length - 1)]);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme, l = AppLocalizations.of(context);
    final list = shown;
    return Align(
      alignment: const Alignment(0, -.6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: c.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.outline.withValues(alpha: .25)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.search, size: 18, color: c.outline),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: field,
                          focusNode: focus,
                          autofocus: true,
                          onChanged: typed,
                          style: TextStyle(fontSize: 17, color: c.onSurface),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: l.paletteHint,
                            hintStyle: TextStyle(fontSize: 17, color: c.outline),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: .5, color: c.outline.withValues(alpha: .3)),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(l.paletteNone, style: TextStyle(fontSize: 14, color: c.outline)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      controller: scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: list.length,
                      itemExtent: 44,
                      itemBuilder: (_, i) {
                        final item = list[i];
                        return MouseRegion(
                          onHover: (_) => at == i ? null : setState(() => at = i),
                          child: GestureDetector(
                            onTap: () => run(item),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: i == at ? (settings.accent == 0 ? c.surface : c.primary.withValues(alpha: .3)) : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(item.icon, size: 18, color: c.onSurfaceVariant),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 15, color: c.onSurface),
                                    ),
                                  ),
                                  Text(item.keys.isNotEmpty ? item.keys : item.group, style: TextStyle(fontSize: 13, color: c.outline)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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
