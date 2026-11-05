import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'chat_page.dart';
import 'cron_page.dart';
import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';

/// The notice a tapped push named, for the chat page to open (set before or after it is up).
final openedNotice = ValueNotifier<String?>(null);

/// The notice picked to discuss, for the chat page to start a chat on.
final discussedNotice = ValueNotifier<Notice?>(null);

/// How many notices came after the newest the Notifications page showed.
final unreadNotices = ValueNotifier(0);

/// The push watcher's notices, newest first; none while it sent nothing yet.
Future<List<Notice>> fetchNotices() async {
  // the file sits in the server's Hermes home, which the cron jobs tell
  final home = parseCronJobs(await serverApi('GET', '/api/cron/jobs') ?? '').map((j) => '${j.raw['hermes_home'] ?? ''}');
  final path = home.where((h) => h.isNotEmpty).firstOrNull;
  if (path == null) return [];
  try {
    final file = jsonDecode(await serverApi('GET', '/api/files/read', query: {'path': noticesPath(path)}) ?? '{}') as Map;
    if (file['data_url'] case final String url) return parseNotices(utf8.decode(UriData.parse(url).contentAsBytes(), allowMalformed: true));
  } on HttpException catch (e) {
    if (!e.message.toLowerCase().contains('not found')) rethrow; // nothing sent yet
  }
  return [];
}

/// Counts the notices of [list] sent after the newest one shown, all of them once [seen]. The first count takes
/// those already there as seen, not to greet with hundreds.
void countUnread(List<Notice> list, {bool seen = false}) {
  final newest = list.map((n) => n.at).nonNulls.fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
  if (seen || settings.noticesSeen == null) {
    settings.noticesSeen = newest ?? settings.noticesSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  final since = settings.noticesSeen!;
  unreadNotices.value = list.where((n) => n.at?.isAfter(since) ?? false).length;
}

/// The notices the server's push watcher sent, newest first: cron answers, script outputs (the dispatcher's
/// pushes, blocks and CI), failures. Read from a file on the server: no model, no token.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.open});

  /// A notice to show at once, the one a tapped push named.
  final String? open;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Notice>? notices;
  Object? error;

  @override
  void initState() {
    super.initState();
    load().then((_) {
      if (notices?.where((n) => n.id == widget.open).firstOrNull case final n? when mounted) show(n);
    });
  }

  Future<void> load() async {
    try {
      final list = await fetchNotices();
      countUnread(list, seen: true);
      if (mounted) {
        setState(() {
          notices = list;
          error = null;
        });
      }
    } catch (e) {
      debugPrint('Notifications: $e');
      if (mounted) setState(() => error = e);
    }
  }

  void show(Notice n) => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => _NoticePage(notice: n)));

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final format = DateFormat.MMMd(Localizations.localeOf(context).toString()).add_Hm();
    return PageFrame(
      title: l.notifications,
      child: switch ((notices, error)) {
        (_, final Object e) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              serverErrorText(l, e),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.onSurfaceVariant),
            ),
          ),
        ),
        (null, _) => const Center(child: CupertinoActivityIndicator()),
        (final List<Notice> list, _) when list.isEmpty => Center(
          child: Text(l.notificationsEmpty, style: TextStyle(color: c.onSurfaceVariant)),
        ),
        (final List<Notice> list, _) => RefreshIndicator(
          onRefresh: load,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 48),
            children: [
              CupertinoListSection.insetGrouped(
                backgroundColor: c.surface,
                decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                separatorColor: c.outline.withValues(alpha: .2),
                children: [
                  for (final n in list)
                    Hover(
                      radius: 0,
                      child: CupertinoListTile(
                        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                        title: Text(
                          [if (n.at != null) format.format(n.at!), n.title].join(' · '),
                          style: TextStyle(fontSize: 15, color: n.failed ? const Color(0xFFD93025) : c.onSurface),
                        ),
                        subtitle: Text(
                          n.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.outline),
                        ),
                        trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: c.outline),
                        onTap: () => show(n),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      },
    );
  }
}

/// One notice in full, its Markdown rendered and selectable.
class _NoticePage extends StatelessWidget {
  const _NoticePage({required this.notice});
  final Notice notice;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final at = notice.at == null ? '' : DateFormat.yMMMd(Localizations.localeOf(context).toString()).add_Hm().format(notice.at!);
    return PageFrame(
      title: notice.title,
      action: TextButton(onPressed: () => discussedNotice.value = notice, child: Text(AppLocalizations.of(context).noticeDiscuss)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (at.isNotEmpty) Text(at, style: TextStyle(fontSize: 13, color: c.outline)),
            const SizedBox(height: 8),
            ReplyMarkdown(
              notice.text,
              style: TextStyle(fontSize: 16, height: 1.45, color: notice.failed ? const Color(0xFFD93025) : c.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
