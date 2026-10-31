import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'cron_page.dart';
import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';

/// What Hermes remembers: about the user and its own notes, each entry fixable or forgettable.
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  List<Memory>? items;
  Object? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final body = await serverApi('GET', '/api/learning/graph');
      if (body == null) throw StateError('no server');
      if (!mounted) return;
      setState(() {
        items = parseMemories(body);
        error = null;
      });
    } catch (e) {
      debugPrint('Memory: $e');
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> edit(Memory m) async {
    final saved = await Navigator.of(context).push<bool>(CupertinoPageRoute(builder: (_) => MemoryEditPage(memory: m)));
    if (saved == true) load(); // the entry's id changed with its text
  }

  Future<bool> forget(Memory m) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showChoices<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        message: Text(l.memoryForgetMessage),
        actions: [
          CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: Text(l.memoryForget)),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
      ),
    );
    if (ok != true) return false;
    try {
      await serverApi('DELETE', '/api/learning/node', body: {'id': m.id});
      load(); // the other entries' ids shift
      return true;
    } catch (e) {
      debugPrint('Memory forget: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.deleteFailed(e is HttpException ? e.message : '$e'))));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final small = TextStyle(fontSize: 13, color: c.outline);
    final list = items;
    Widget section(String title, List<Memory> entries) => CupertinoListSection.insetGrouped(
      backgroundColor: c.surface,
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      separatorColor: c.outline.withValues(alpha: .2),
      header: Text(title.toUpperCase(), style: small),
      children: [
        for (final m in entries)
          Dismissible(
            key: ValueKey(m.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => forget(m),
            onDismissed: (_) => setState(() => list!.remove(m)),
            background: Container(
              color: const Color(0xFF9E1B1B),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(CupertinoIcons.trash, color: Colors.white),
            ),
            child: CupertinoListTile(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              title: Text(m.title, maxLines: 2, style: TextStyle(fontSize: 16, color: c.onSurface)),
              subtitle: m.at == null ? null : Text(DateFormat.yMMMd('${Localizations.localeOf(context)}').format(m.at!), style: small),
              trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: c.outline),
              onTap: () => edit(m),
            ),
          ),
      ],
    );
    return PageFrame(
      title: l.memory,
      child: list == null && error == null
          ? const Center(child: CupertinoActivityIndicator())
          : RefreshIndicator.adaptive(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 48),
                children: [
                  if (error != null || list!.isEmpty) ...[
                    const SizedBox(height: 40),
                    Icon(CupertinoIcons.lightbulb, size: 56, color: c.outline),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                      child: Text(
                        error != null ? serverErrorText(l, error is StateError ? null : error) : l.memoryEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: c.outline),
                      ),
                    ),
                  ] else ...[
                    if (list.where((m) => m.profile).toList() case final about when about.isNotEmpty) section(l.memoryAboutYou, about),
                    if (list.where((m) => !m.profile).toList() case final notes when notes.isNotEmpty) section(l.memoryNotes, notes),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(36, 8, 36, 0),
                      child: Text(l.memoryFooter, style: small),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// One memory entry in full, to correct; pops true once saved.
class MemoryEditPage extends StatefulWidget {
  const MemoryEditPage({super.key, required this.memory});
  final Memory memory;

  @override
  State<MemoryEditPage> createState() => _MemoryEditPageState();
}

class _MemoryEditPageState extends State<MemoryEditPage> {
  final text = TextEditingController();
  String? loaded; // the entry as the server has it
  Object? error;
  var saving = false;

  @override
  void initState() {
    super.initState();
    text.addListener(() => setState(() {}));
    load();
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final body = await serverApi('GET', '/api/learning/node', query: {'id': widget.memory.id});
      final content = switch (body == null ? null : jsonDecode(body)) {
        {'content': final String c} => c,
        _ => throw StateError('no server'),
      };
      if (mounted) setState(() => text.text = loaded = content);
    } catch (e) {
      debugPrint('Memory entry: $e');
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> save() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => saving = true);
    try {
      await serverApi('PUT', '/api/learning/node', body: {'id': widget.memory.id, 'content': text.text.trim()});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Memory save: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.cronActionFailed(e is HttpException ? e.message : serverErrorText(l, null)))));
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final changed = loaded != null && text.text.trim().isNotEmpty && text.text.trim() != loaded!.trim();
    return PageFrame(
      title: widget.memory.profile ? l.memoryAboutYou : l.memoryNotes,
      action: saving
          ? const Padding(padding: EdgeInsets.all(14), child: CupertinoActivityIndicator())
          : TextButton(
              onPressed: changed ? save : null,
              child: Text(l.cronSave, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
      child: error != null
          ? Padding(
              padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
              child: Text(serverErrorText(l, error is StateError ? null : error), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.outline)),
            )
          : loaded == null
          ? const Center(child: CupertinoActivityIndicator())
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                  child: TextField(
                    controller: text,
                    maxLines: null,
                    minLines: 4,
                    style: TextStyle(fontSize: 16, height: 1.4, color: c.onSurface),
                    decoration: const InputDecoration.collapsed(hintText: null),
                  ),
                ),
              ],
            ),
    );
  }
}
