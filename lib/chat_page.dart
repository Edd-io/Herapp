import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import 'agents_page.dart';
import 'hermes.dart';
import 'kanban_page.dart';
import 'l10n/app_localizations.dart';
import 'memory_page.dart';
import 'model_sheet.dart';
import 'quota_page.dart';
import 'settings.dart';
import 'vault_page.dart';

class Chat {
  Chat({this.stored = '', this.name = ''}) : loaded = stored.isEmpty;
  final msgs = <Msg>[];
  String model = settings.model;
  late String effort = stored.isEmpty ? settings.effort : ''; // a reopened chat keeps the effort it ran with
  String stored; // server session id, '' until the first message creates it
  String name; // server title
  bool loaded; // transcript fetched (always for a chat started here)
  bool loading = false;
  double? context; // share of the context window the server reports, null until known
  double cost = 0; // USD spent on it so far, as the server counts it
  // runtime session on the current gateway connection, and the model it runs
  Gateway? on;
  String live = '';
  String applied = '';
  Future<void>? warming; // the resume [open] started
  String get title => name.isNotEmpty ? name : msgs.firstOrNull?.text ?? ''; // only titled chats are listed
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with SingleTickerProviderStateMixin {
  var chats = [Chat()];
  late Chat chat = chats.first;
  final input = TextEditingController();
  late final focus = FocusNode(onKeyEvent: enterKey);
  final searchFocus = FocusNode();
  final scroll = ScrollController();
  final models = ValueNotifier<Models>((list: const [], loading: false, error: null));
  late final drawer = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  StreamSubscription<GatewayEvent>? sub; // events of the running turn
  bool streaming = false;
  Msg? fresh; // latest user message, animated on arrival
  bool atBottom = true;
  String query = '';
  List<Found> found = []; // conversations whose messages match [query]
  final pending = <Attachment>[]; // photos and files for the next message
  final pane = GlobalKey<NavigatorState>();
  final paneRefresh = ValueNotifier(0);
  List<Slash> slashes = []; // skills matching the `/` being typed
  String slashFor = '';

  @override
  void initState() {
    super.initState();
    input.addListener(() {
      setState(() {});
      complete();
    });
    scroll.addListener(() {
      final b = scroll.position.extentAfter < 40;
      if (b != atBottom) setState(() => atBottom = b);
    });
    loadModels();
    loadSessions();
  }

  /// Lists the server's stored conversations in the sidebar, after the chats not saved there yet.
  Future<void> loadSessions() async {
    try {
      final g = await gateway();
      if (g == null) return;
      final rows = parseSessions(await g.call('session.list', {'limit': 50}));
      if (!mounted) return;
      final known = {for (final c in chats) c.stored: c};
      setState(() {
        chats = [
          ...chats.where((c) => c.stored.isEmpty),
          for (final r in rows) (known[r.id]?..name = r.title) ?? Chat(stored: r.id, name: r.title),
          // the server's list is the truth; only the open chat stays if it's missing from it
          if (chat.stored.isNotEmpty && !rows.any((r) => r.id == chat.stored)) chat,
        ];
      });
    } catch (e) {
      debugPrint('Sessions: $e');
    }
  }

  /// Attaches [c] to a runtime session on [g]: creates it on the first message, resumes it after a
  /// reconnect, and switches its model when another one was picked.
  Future<String> attach(Gateway g, Chat c) async {
    await c.warming;
    if (!identical(c.on, g)) {
      final created = c.stored.isEmpty;
      final r = created
          ? await g.call('session.create', {
              if (c.model.contains('/')) ...{'provider': c.model.substring(0, c.model.indexOf('/')), 'model': modelName(c.model)},
              if (c.effort.isNotEmpty && thinks(c.model)) 'reasoning_effort': c.effort,
            })
          : await g.call('session.resume', {'session_id': c.stored, 'lazy': true, 'omit_messages': true});
      c
        ..stored = '${r['stored_session_id'] ?? c.stored}'
        ..live = '${r['session_id']}'
        ..on = g
        ..applied = created ? c.model : c.applied;
    }
    if (c.model.contains('/') && c.model != c.applied) {
      final provider = c.model.substring(0, c.model.indexOf('/'));
      await g.call('config.set', {'key': 'model', 'value': '${modelName(c.model)} --provider $provider', 'session_id': c.live});
      c.applied = c.model;
    }
    return c.live;
  }

  /// Fetches a stored conversation's transcript, while [warm] readies its session in the background.
  Future<void> open(Chat c) async {
    setState(() => c.loading = true);
    try {
      final g = await gateway();
      if (g == null) throw StateError('no server');
      c.warming = warm(g, c);
      final body = await serverApi('GET', '/api/sessions/${Uri.encodeComponent(c.stored)}/messages');
      c
        ..msgs.clear()
        ..msgs.addAll(transcript((jsonDecode(body ?? '{}') as Map)['messages']))
        ..loaded = true;
      loadCost(c);
    } catch (e) {
      debugPrint('Session: $e');
      if (mounted) c.msgs.add(Msg(false, '⚠️ ${serverErrorText(AppLocalizations.of(context), e is StateError ? null : e)}'));
    }
    if (!mounted) return;
    setState(() => c.loading = false);
    if (identical(c, chat)) toBottom(jump: true);
  }

  /// Reads what [c] has cost so far: the provider's figure when it gave one, else the server's estimate.
  Future<void> loadCost(Chat c) async {
    try {
      final body = await serverApi('GET', '/api/sessions/${Uri.encodeComponent(c.stored)}');
      if (jsonDecode(body ?? '{}') case {'estimated_cost_usd': final num estimated} && final Map s when mounted) {
        setState(
          () => c.cost = (s['actual_cost_usd'] is num && s['actual_cost_usd'] > 0 ? s['actual_cost_usd'] as num : estimated).toDouble(),
        );
      }
    } catch (e) {
      debugPrint('Cost: $e');
    }
  }

  /// Resumes [c] with its agent built (a lazy session knows no context use until its next reply), then
  /// reads its model and how full its context is. A failure is left to [attach] to retry.
  Future<void> warm(Gateway g, Chat c) async {
    try {
      final r = await g.call('session.resume', {'session_id': c.stored, 'omit_messages': true});
      final info = r['info'] is Map ? r['info'] as Map : const {};
      c
        ..live = '${r['session_id']}'
        ..on = g;
      if (info case {'provider': final String p, 'model': final String m} when p.isNotEmpty && m.isNotEmpty) {
        c.model = c.applied = '$p/$m';
      }
      if (mounted) setState(() {});
      g.call('session.context_breakdown', {'session_id': c.live}).then((b) {
        if (b['context_max'] case final num max when max > 0 && c.context == null && mounted) setState(() => c.context = contextOf(b));
      }).ignore();
    } catch (e) {
      debugPrint('Warm: $e');
    }
  }

  /// Refreshes the server's model list; a choice the server no longer offers falls back to its default.
  Future<void> loadModels() async {
    models.value = (list: models.value.list, loading: true, error: null);
    try {
      final r = await serverOptions();
      if (!mounted) return;
      if (r == null) {
        models.value = (list: const [], loading: false, error: serverErrorText(AppLocalizations.of(context), null));
        return;
      }
      models.value = (list: r.models, loading: false, error: null);
      if (!r.models.any((m) => m.id == settings.model)) {
        settings.model = r.models.any((m) => m.id == r.current) ? r.current : r.models.firstOrNull?.id ?? '';
      }
      if (!mounted) return;
      setState(() {
        if (chat.msgs.isEmpty && !r.models.any((m) => m.id == chat.model)) chat.model = settings.model;
      });
    } catch (e) {
      debugPrint('Models: $e');
      if (!mounted) return;
      models.value = (list: models.value.list, loading: false, error: serverErrorText(AppLocalizations.of(context), e));
    }
  }

  String providerOf(String id) => models.value.list.where((m) => m.id == id).firstOrNull?.provider ?? '';

  /// Whether [id] takes a reasoning effort (assumed while the list is unknown).
  bool thinks(String id) => models.value.list.where((m) => m.id == id).firstOrNull?.reasoning ?? true;

  @override
  void dispose() {
    sub?.cancel();
    drawer.dispose();
    paneRefresh.dispose();
    input.dispose();
    focus.dispose();
    searchFocus.dispose();
    scroll.dispose();
    models.dispose();
    super.dispose();
  }

  /// A keyboard's Enter sends the message; Shift+Enter, or Enter finishing an IME composition, types as usual.
  KeyEventResult enterKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || (e.logicalKey != LogicalKeyboardKey.enter && e.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed || input.value.composing.isValid) return KeyEventResult.ignored;
    send();
    return KeyEventResult.handled;
  }

  void send() {
    final text = input.text.trim();
    if ((text.isEmpty && pending.isEmpty) || streaming) return;
    settings.haptic();
    input.clear();
    final m = Msg(true, text, null, [...pending]);
    setState(() {
      pending.clear();
      chat.msgs.add(m);
      fresh = m;
    });
    respond();
  }

  /// Offers the server's skills while a `/name` is typed at the start of the message.
  void complete() {
    final t = input.text;
    if (!t.startsWith('/') || t.contains(RegExp(r'\s'))) {
      slashFor = '';
      if (slashes.isNotEmpty) setState(() => slashes = []);
      return;
    }
    if (t == slashFor) return;
    slashFor = t;
    () async {
      try {
        final g = await gateway();
        if (g == null) return;
        final r = await g.call('complete.slash', {'text': t, if (identical(chat.on, g) && chat.live.isNotEmpty) 'session_id': chat.live});
        if (mounted && input.text == t) setState(() => slashes = parseSlash(r).where((s) => s.skill).take(8).toList());
      } catch (e) {
        debugPrint('Slash: $e');
      }
    }();
  }

  void pickSlash(Slash s) {
    settings.haptic();
    input.value = TextEditingValue(
      text: '${s.text.startsWith('/') ? s.text : '/${s.text}'} ',
      selection: TextSelection.collapsed(offset: s.text.length + (s.text.startsWith('/') ? 1 : 2)),
    );
  }

  /// Adds photos (library or camera) or files to the next message.
  Future<void> attachFiles() async {
    final l = AppLocalizations.of(context);
    final from = await showChoices<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, 'photos'), child: Text(l.attachPhotos)),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, 'camera'), child: Text(l.attachCamera)),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, 'files'), child: Text(l.attachFiles)),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
      ),
    );
    try {
      final picked = switch (from) {
        'photos' => [for (final x in await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2048)) (x, true)],
        'camera' => [
          if (await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2048) case final x?) (x, true),
        ],
        'files' => [for (final x in await openFiles()) (x, false)],
        _ => const <(XFile, bool)>[],
      };
      for (final (x, image) in picked) {
        final bytes = await x.readAsBytes();
        final looksImage = image || RegExp(r'\.(png|jpe?g|gif|webp|heic)$', caseSensitive: false).hasMatch(x.name);
        if (mounted) setState(() => pending.add((name: x.name, bytes: bytes, image: looksImage)));
      }
    } catch (e) {
      debugPrint('Attach: $e');
    }
  }

  /// Sends the last user message to Hermes and streams the reply in; [again] replaces the previous reply.
  Future<void> respond({bool again = false}) async {
    final c = chat;
    final asked = c.msgs.last;
    var prompt = asked.text;
    final turn = c.msgs.where((m) => m.user).length - 1; // the server's user-turn ordinal
    final reply = Msg(false, '');
    setState(() {
      c.msgs.add(reply);
      streaming = true;
    });
    toBottom();
    void fail(Object? e) {
      if (!identical(c, chat) || !streaming) return;
      reply.text += '${reply.text.isEmpty ? '' : '\n\n'}⚠️ ${e is String ? e : serverErrorText(AppLocalizations.of(context), e)}';
      stop();
    }

    try {
      final g = await gateway();
      if (g == null) return fail(null); // no server set
      final sid = await attach(g, c);
      if (!identical(c, chat) || !streaming) return;
      sub = g.events.listen((e) {
        if (e.id case final id?) {
          // only command approvals are shown; other questions (clarify, sudo, secrets) are refused at once
          if (e.type == 'approval' && (e.session == sid || e.session.isEmpty)) {
            setState(() => reply.ask = (id: id, params: e.payload));
            settings.haptic();
          } else {
            g.reply(id, null);
          }
          return;
        }
        if (e.type == 'session.title' && e.payload['session_id'] == c.stored && e.payload['title'] is String) {
          setState(() => c.name = e.payload['title'] as String);
        }
        if (e.session != sid) return;
        switch (e.type) {
          case 'message.delta' when e.payload['text'] is String:
            setState(() => reply.text += e.payload['text'] as String);
            if (atBottom) toBottom(jump: true);
          case 'tool.start':
            final p = e.payload;
            setState(() => reply.tools.add(Tool('${p['tool_id']}', '${p['name']}', '${p['context'] ?? p['preview'] ?? ''}')));
          case 'tool.complete':
            setState(() {
              for (final t in reply.tools.where((t) => t.id == '${e.payload['tool_id']}')) {
                t.done = true;
              }
            });
          case 'request.cancel' when reply.ask?.id == e.payload['id']:
            setState(() => reply.ask = null);
          case 'session.usage':
            setState(() => c.context = contextOf(e.payload['usage']) ?? c.context);
          case 'message.complete':
            final p = e.payload;
            c.context = contextOf(p['usage']) ?? c.context;
            if (reply.text.trim().isEmpty && p['text'] is String) reply.text = p['text'] as String;
            if (p['status'] == 'error') return fail('${p['error'] ?? p['failure_reason'] ?? 'error'}');
            stop();
          case 'error':
            fail('${e.payload['message']}');
        }
      }, onDone: () => fail(const HttpException('connection to Hermes lost')));
      // photos are queued for this turn; a file is staged in the workspace and named in the prompt
      final notes = <String>[];
      for (final f in asked.files.where((f) => f.bytes != null)) {
        final r = f.image
            ? await g.call('image.attach_bytes', {'session_id': sid, 'content_base64': base64Encode(f.bytes!), 'filename': f.name})
            : await g.call('file.attach', {
                'session_id': sid,
                'name': f.name,
                'data_url': 'data:application/octet-stream;base64,${base64Encode(f.bytes!)}',
              });
        if (!f.image || prompt.isEmpty) notes.add('${r[f.image ? 'text' : 'ref_text'] ?? ''}');
      }
      prompt = [prompt, ...notes].where((t) => t.trim().isNotEmpty).join('\n\n');
      // a `/skill` is expanded by the server into the skill's instructions
      var typed = '';
      if (RegExp(r'^/([\w-]+)\s*([\s\S]*)$').firstMatch(asked.text) case final cmd?) {
        try {
          final d = await g.call('command.dispatch', {'name': cmd[1], 'arg': cmd[2]!.trim(), 'session_id': sid});
          if (d['message'] case final String body when body.trim().isNotEmpty && (d['type'] == 'skill' || d['type'] == 'send')) {
            typed = asked.text;
            prompt = [body, ...notes].join('\n\n');
          } else if (d['output'] case final String out) {
            setState(() => reply.text = out);
            return stop();
          }
        } on HttpException catch (e) {
          debugPrint('Dispatch: ${e.message}'); // not a skill: sent as typed
        }
        if (!identical(c, chat) || !streaming) return;
      }
      await g.call('prompt.submit', {
        'session_id': sid,
        'text': prompt,
        if (typed.isNotEmpty) 'title_preview': typed,
        if (again) ...{'truncate_before_user_ordinal': turn, 'confirm_truncate': true},
      });
    } catch (e) {
      debugPrint('Chat: $e');
      fail(e);
    }
  }

  void stop() {
    final g = chat.on;
    if (streaming && g != null && !g.closed && chat.live.isNotEmpty) g.call('session.interrupt', {'session_id': chat.live}).ignore();
    sub?.cancel();
    sub = null;
    if (chat.msgs.lastOrNull case final m? when !m.user) {
      m.ask = null; // an interrupted turn drops its question
      if (m.text.isEmpty && m.tools.isEmpty) chat.msgs.removeLast();
    }
    setState(() => streaming = false);
    loadSessions(); // a first message adds the chat to the server's list
    if (chat.stored.isNotEmpty) loadCost(chat);
  }

  /// Sends the user's [choice] for the command [m] is waiting on.
  void answer(Msg m, String choice) {
    final ask = m.ask;
    if (ask == null) return;
    settings.haptic();
    chat.on?.reply(ask.id, {'choice': choice});
    setState(() => m.ask = null);
  }

  void regenerate() {
    stop();
    setState(() => chat.msgs.removeLast());
    respond(again: true);
  }

  void newChat() {
    stop();
    if (chat.msgs.isNotEmpty) chats.insert(0, chat = Chat());
    setState(() {});
    closeDrawer();
  }

  /// Asks, then deletes [c] from the server (a chat never sent is only dropped); false if kept.
  Future<bool> confirmDelete(Chat c) async {
    final l = AppLocalizations.of(context);
    final ok = await showChoices<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        message: Text(l.deleteChatMessage),
        actions: [
          CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: Text(l.deleteChat)),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
      ),
    );
    if (ok != true || c.stored.isEmpty) return ok == true;
    try {
      final g = await gateway();
      if (g == null) throw const HttpException('no server');
      if (identical(c, chat)) stop();
      if (identical(c.on, g) && c.live.isNotEmpty) {
        // the server refuses to delete a session that is still open
        await g.call('session.close', {'session_id': c.live}).catchError((Object _) => const {});
        c
          ..on = null
          ..live = '';
      }
      await g.call('session.delete', {'session_id': c.stored});
      return true;
    } catch (e) {
      debugPrint('Delete: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.deleteFailed(e is HttpException ? e.message : '$e'))));
      }
      return false;
    }
  }

  void deleted(Chat c) {
    if (identical(c, chat)) {
      stop();
      chats.insert(0, chat = Chat());
    }
    setState(() => chats.remove(c));
  }

  void select(Chat c) {
    stop();
    setState(() => chat = c);
    closeDrawer();
    if (!c.loaded && !c.loading) open(c);
    toBottom(jump: true);
  }

  /// Model picker sheet, grouped by provider.
  Future<void> pickModel() async {
    loadModels();
    final id = await showModelSheet(
      context,
      models: models,
      current: chat.model,
      effort: chat.effort,
      onEffort: (e) => setState(() => chat.effort = settings.effort = e),
    );
    if (id == null || !mounted) return;
    settings.haptic();
    setState(() => chat.model = settings.model = id);
  }

  void openDrawer() {
    focus.unfocus();
    loadSessions();
    drawer.animateTo(1, curve: Curves.easeOutCubic);
  }

  /// Hides the menu; on a wide window, where it stays, closes the page beside it instead.
  void closeDrawer() {
    drawer.animateTo(0, curve: Curves.easeOutCubic);
    pane.currentState?.popUntil((r) => r.isFirst);
  }

  bool get wide => MediaQuery.sizeOf(context).width >= wideWidth;

  /// The menu's pages, in order; ⌘1… opens them.
  List<(String, IconData, Widget)> pages(AppLocalizations l) => [
    (l.quotas, CupertinoIcons.gauge, const QuotaPage()),
    (l.agents, CupertinoIcons.sparkles, const AgentsPage()),
    (l.kanban, CupertinoIcons.square_split_2x1, const KanbanPage()),
    (l.memory, CupertinoIcons.lightbulb, const MemoryPage()),
    (l.vault, CupertinoIcons.lock_shield, const VaultPage()),
  ];

  void openPage(Widget page) {
    closeDrawer();
    show(page);
  }

  Future<void> openSettings() async {
    await showPageSheet<void>(context, (_) => const SettingsSheet());
    // server, auth or tunnel may have changed
    dropGateway();
    loadModels();
    loadSessions();
  }

  void findChats() {
    if (!wide) openDrawer();
    searchFocus.requestFocus();
  }

  /// Keyboard commands (⌘ on Apple keyboards, Ctrl elsewhere): new chat, search, settings, the menu's pages; Esc closes.
  List<(String, SingleActivator, VoidCallback)> commands(AppLocalizations l) {
    final apple = const [TargetPlatform.macOS, TargetPlatform.iOS].contains(defaultTargetPlatform);
    SingleActivator key(LogicalKeyboardKey k) => SingleActivator(k, meta: apple, control: !apple);
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
    ];
    return [
      (l.newChat, key(LogicalKeyboardKey.keyN), newChat),
      (l.search, key(LogicalKeyboardKey.keyK), findChats),
      (l.settings, key(LogicalKeyboardKey.comma), openSettings),
      for (final (i, (label, _, page)) in pages(l).indexed) (label, key(digits[i]), () => openPage(page)),
    ];
  }

  /// Opens a menu [page]: over everything on a phone, beside the menu on a wide window.
  void show(Widget page) => (wide ? pane.currentState! : Navigator.of(context)).push(CupertinoPageRoute<void>(builder: (_) => page));

  // the chat as rebuilt by every setState, for the wide window's pane where pages open beside the menu
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    paneRefresh.value++;
  }

  void toBottom({bool jump = false}) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!scroll.hasClients) return;
    final max = scroll.position.maxScrollExtent;
    jump ? scroll.jumpTo(max) : scroll.animateTo(max, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // a Mac lists the commands in its menu bar, which also answers their keys
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final body = CallbackShortcuts(
      bindings: {
        if (!mac)
          for (final (_, key, run) in commands(l)) key: run,
        const SingleActivator(LogicalKeyboardKey.escape): closeDrawer,
      },
      child: Focus(autofocus: true, child: _frame()),
    );
    if (!mac) return body;
    PlatformMenuItem item((String, SingleActivator, VoidCallback) x) => PlatformMenuItem(label: x.$1, shortcut: x.$2, onSelected: x.$3);
    PlatformMenuItemGroup provided(List<PlatformProvidedMenuItemType> types) =>
        PlatformMenuItemGroup(members: [for (final t in types) PlatformProvidedMenuItem(type: t)]);
    final all = commands(l);
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Herapp',
          menus: [
            provided([PlatformProvidedMenuItemType.about]),
            PlatformMenuItemGroup(members: [item(all[2])]),
            provided([
              PlatformProvidedMenuItemType.hide,
              PlatformProvidedMenuItemType.hideOtherApplications,
              PlatformProvidedMenuItemType.showAllApplications,
            ]),
            provided([PlatformProvidedMenuItemType.quit]),
          ],
        ),
        PlatformMenu(label: l.menuFile, menus: [item(all[0]), item(all[1])]),
        PlatformMenu(
          label: l.menuView,
          menus: [
            PlatformMenuItemGroup(members: [for (final x in all.skip(3)) item(x)]),
            provided([PlatformProvidedMenuItemType.toggleFullScreen]),
          ],
        ),
        PlatformMenu(
          label: l.menuWindow,
          menus: [
            provided([PlatformProvidedMenuItemType.minimizeWindow, PlatformProvidedMenuItemType.zoomWindow]),
            provided([PlatformProvidedMenuItemType.arrangeWindowsInFront]),
          ],
        ),
      ],
      child: body,
    );
  }

  Widget _frame() {
    final c = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context).width;
    final width = screen * .82;
    late final main = _main(c); // the wide layout builds it in its pane
    final sidebar = _sidebar(c);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.surfaceContainerLow,
        // a wide window keeps the menu beside the chat, as desktop chat apps do
        body: wide
            ? Row(
                children: [
                  SizedBox(width: 300, child: sidebar),
                  Expanded(
                    // menu pages open here, beside the menu
                    child: Navigator(
                      key: pane,
                      onGenerateRoute: (_) => PageRouteBuilder<void>(
                        pageBuilder: (context, _, _) => ValueListenableBuilder(
                          valueListenable: paneRefresh,
                          builder: (context, _, _) => _main(Theme.of(context).colorScheme),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : GestureDetector(
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
                if (wide) const SizedBox(width: 52) else _IconBtn(onTap: openDrawer, child: _MenuIcon(c.onSurface)),
                Expanded(
                  // empty: no title, the centered pill is the picker
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
                                modelName(chat.model),
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
            child: chat.loading
                ? const Center(child: CupertinoActivityIndicator())
                : chat.msgs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppLocalizations.of(context).emptyHeadline,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: c.onSurface),
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: pickModel,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(22)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          chat.model.isEmpty ? AppLocalizations.of(context).model : modelName(chat.model),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.onSurface),
                                        ),
                                        if ([
                                              providerOf(chat.model),
                                              if (chat.effort.isNotEmpty && thinks(chat.model))
                                                effortText(AppLocalizations.of(context), chat.effort),
                                            ].where((t) => t.isNotEmpty).join(' · ')
                                            case final p when p.isNotEmpty)
                                          Text(
                                            p,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 12, color: c.outline),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(CupertinoIcons.chevron_down, size: 13, color: c.outline),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      LayoutBuilder(
                        builder: (context, box) {
                          final side = math.max(16.0, (box.maxWidth - 760) / 2); // a readable column, scrollable edge to edge
                          return ListView.builder(
                            controller: scroll,
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(side, 8, side, 24),
                            itemCount: chat.msgs.length,
                            itemBuilder: (_, i) => _message(c, chat.msgs[i], i == chat.msgs.length - 1),
                          );
                        },
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
          readable(_composer(c), width: 792),
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
          if (m.tools.isNotEmpty) _Tools(m.tools, live: live),
          if (m.ask case final ask?) _approval(c, m, ask.params),
          if (m.text.trim().isNotEmpty)
            _Markdown(m.text.trimLeft(), style: body.copyWith(color: c.onSurface)) // text after a tool call starts with blank lines
          else if (live && m.ask == null && m.tools.every((t) => t.done))
            _PulseDot(c.onSurface),
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

  /// The card asking whether Hermes may run a command, with the choices the server allows.
  Widget _approval(ColorScheme c, Msg m, Map p) {
    final l = AppLocalizations.of(context);
    final choices = [
      for (final k
          in p['choices'] is List && (p['choices'] as List).isNotEmpty ? p['choices'] as List : const ['once', 'session', 'always', 'deny'])
        if (!(k == 'session' && p['allow_session'] == false) && !(k == 'always' && p['allow_permanent'] == false)) '$k',
    ];
    Widget button(String k) {
      final main = k == 'once';
      return GestureDetector(
        onTap: () => answer(m, k),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(color: main ? c.primary : c.surface, borderRadius: BorderRadius.circular(20)),
          child: Text(
            switch (k) {
              'once' => l.approveOnce,
              'session' => l.approveSession,
              'always' => l.approveAlways,
              'deny' => l.approveDeny,
              _ => k,
            },
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: main ? c.onPrimary : (k == 'deny' ? const Color(0xFFD93025) : c.onSurface),
            ),
          ),
        ),
      );
    }

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

  Widget _composer(ColorScheme c) {
    final hasText = input.text.trim().isNotEmpty || pending.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (slashes.isNotEmpty) _slashList(c),
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
      ],
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
          GestureDetector(
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
      ],
    ),
  );

  Widget _composerRow(ColorScheme c, bool hasText) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: streaming ? null : attachFiles,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.surfaceContainerHighest, shape: BoxShape.circle),
              child: Icon(CupertinoIcons.add, size: 22, color: c.onSurface),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(left: 16, right: 4),
              decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(22)),
              child: LayoutBuilder(
                builder: (context, box) {
                  final style = TextStyle(fontSize: 17, color: c.onSurface);
                  // multi-line once the text no longer fits on one line beside the ring and the send button
                  final showRing = chat.msgs.isNotEmpty; // nothing to measure before the first message
                  final multiline = (TextPainter(
                    text: TextSpan(text: input.text, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    maxLines: 1,
                  )..layout(maxWidth: box.maxWidth - (showRing ? 8 + 20 + 12 : 0) - 36)).didExceedMaxLines;
                  final ring = _ContextRing(
                    chat.context ?? contextUse([for (final m in chat.msgs) m.text, input.text].join()),
                    cost: chat.cost,
                  );
                  final sendBtn = AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: !hasText && !streaming
                        ? const SizedBox(height: 44)
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
                              hintText: AppLocalizations.of(context).composerHint,
                              hintStyle: TextStyle(fontSize: 17, color: c.outline),
                            ),
                          ),
                        ),
                      ),
                      if (!showRing)
                        sendBtn
                      else if (multiline)
                        // ring stacked above the send button
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(padding: const EdgeInsets.only(top: 10, bottom: 6), child: ring),
                              sendBtn,
                            ],
                          ),
                        )
                      else ...[
                        Padding(padding: const EdgeInsets.only(left: 8, right: 12, bottom: 12), child: ring),
                        sendBtn,
                      ],
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
    final known = chats.where((ch) => ch.stored == f.id).firstOrNull;
    if (known == null) setState(() => chats.add(Chat(stored: f.id, name: f.title)));
    select(known ?? chats.last);
  }

  Widget _sidebar(ColorScheme c) {
    final q = query.toLowerCase();
    final listed = chats.where((ch) => ch.title.isNotEmpty && ch.title.toLowerCase().contains(q));
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
            tile(AppLocalizations.of(context).newChat, icon: CupertinoIcons.square_pencil, onTap: newChat),
            for (final (label, icon, page) in pages(AppLocalizations.of(context))) tile(label, icon: icon, onTap: () => openPage(page)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: Text(
                AppLocalizations.of(context).chats,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.outline),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
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
                      GestureDetector(
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
          GestureDetector(
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
          if (open) ...rows,
        ],
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

/// Menu icon with two uneven bars.
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

/// Pulsing dot shown while waiting for the first reply chunk.
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
        a: style.copyWith(decoration: TextDecoration.underline),
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
              CupertinoButton(
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
