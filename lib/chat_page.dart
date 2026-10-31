import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'cron_page.dart';
import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'quota_page.dart';
import 'settings.dart';

/// Server models; [error] is the failure to show (see [serverErrorText]), null when the list loaded.
typedef Models = ({List<Model> list, bool loading, String? error});

class Chat {
  Chat({this.stored = '', this.name = ''}) : loaded = stored.isEmpty;
  final msgs = <Msg>[];
  String model = settings.model;
  String stored; // server session id, '' until the first message creates it
  String name; // server title
  bool loaded; // transcript fetched (always for a chat started here)
  bool loading = false;
  double? context; // share of the context window the server reports, null until known
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
  final focus = FocusNode();
  final scroll = ScrollController();
  final models = ValueNotifier<Models>((list: const [], loading: false, error: null));
  late final drawer = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  StreamSubscription<GatewayEvent>? sub; // events of the running turn
  bool streaming = false;
  Msg? fresh; // latest user message, animated on arrival
  bool atBottom = true;
  String query = '';

  @override
  void initState() {
    super.initState();
    input.addListener(() => setState(() {}));
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
    } catch (e) {
      debugPrint('Session: $e');
      if (mounted) c.msgs.add(Msg(false, '⚠️ ${serverErrorText(AppLocalizations.of(context), e is StateError ? null : e)}'));
    }
    if (!mounted) return;
    setState(() => c.loading = false);
    if (identical(c, chat)) toBottom(jump: true);
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

  @override
  void dispose() {
    sub?.cancel();
    drawer.dispose();
    input.dispose();
    focus.dispose();
    scroll.dispose();
    models.dispose();
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

  /// Sends the last user message to Hermes and streams the reply in; [again] replaces the previous reply.
  Future<void> respond({bool again = false}) async {
    final c = chat;
    final prompt = c.msgs.last.text;
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
      await g.call('prompt.submit', {
        'session_id': sid,
        'text': prompt,
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
    final ok = await showCupertinoModalPopup<bool>(
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
    final c = Theme.of(context).colorScheme;
    loadModels();
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: c.surface,
      barrierColor: Colors.black.withValues(alpha: .4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => _ModelSheet(models: models, current: chat.model),
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
                                        if (providerOf(chat.model) case final p when p.isNotEmpty)
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
          if (m.tools.isNotEmpty) _Tools(m.tools, live: live),
          if (m.ask case final ask?) _approval(c, m, ask.params),
          if (m.text.trim().isNotEmpty)
            _StreamText(m.text.trimLeft(), style: body.copyWith(color: c.onSurface)) // text after a tool call starts with blank lines
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
                  final ring = _ContextRing(chat.context ?? contextUse([for (final m in chat.msgs) m.text, input.text].join()));
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
                        onChanged: (v) => setState(() => query = v),
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
            tile(
              AppLocalizations.of(context).quotas,
              icon: CupertinoIcons.gauge,
              onTap: () {
                closeDrawer();
                Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => const QuotaPage()));
              },
            ),
            tile(
              AppLocalizations.of(context).cron,
              icon: CupertinoIcons.clock,
              onTap: () {
                closeDrawer();
                Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => const CronPage()));
              },
            ),
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
                ],
              ),
            ),
            tile(
              AppLocalizations.of(context).settings,
              icon: CupertinoIcons.gear,
              onTap: () async {
                await showCupertinoSheet(context: context, builder: (_) => const SettingsSheet());
                // server, auth or tunnel may have changed
                dropGateway();
                loadModels();
                loadSessions();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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

/// Text whose newly appended chunks fade in.
class _StreamText extends StatefulWidget {
  const _StreamText(this.text, {required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_StreamText> createState() => _StreamTextState();
}

class _StreamTextState extends State<_StreamText> with SingleTickerProviderStateMixin {
  static const fade = Duration(milliseconds: 350);
  final marks = <(int, Duration)>[]; // (chunk start, arrival time)
  Duration now = Duration.zero;
  Ticker? ticker; // created only if the text grows

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

/// How full the context window is, as a ring; tap for the percentage.
class _ContextRing extends StatelessWidget {
  const _ContextRing(this.used);
  final double used;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Tooltip(
      message: AppLocalizations.of(context).contextUsage((used * 100).round()),
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

class _ModelSheet extends StatelessWidget {
  const _ModelSheet({required this.models, required this.current});
  final ValueListenable<Models> models;
  final String current;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
      child: ValueListenableBuilder<Models>(
        valueListenable: models,
        builder: (context, m, _) {
          final providers = {for (final x in m.list) x.provider};
          final note = switch (m) {
            (list: [], loading: true, error: _) => const Center(child: CupertinoActivityIndicator()),
            (list: [], loading: _, error: final String e) => Text(e, textAlign: TextAlign.center),
            (list: [], loading: _, error: _) => Text(l.modelsNone, textAlign: TextAlign.center),
            _ => null,
          };
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    l.model,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                  ),
                  // refreshing an already shown list
                  if (m.loading && m.list.isNotEmpty) ...[const SizedBox(width: 8), const CupertinoActivityIndicator(radius: 8)],
                ],
              ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(fontSize: 15, color: c.outline),
                    child: note,
                  ),
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
                                p.isEmpty ? '' : p[0].toUpperCase(),
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
                            for (final (i, x) in m.list.where((x) => x.provider == p).indexed) ...[
                              if (i > 0) Divider(height: 1, indent: 16, color: c.outline.withValues(alpha: .15)),
                              _ModelRow(x, selected: x.id == current),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                m.name,
                style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: c.onSurface),
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
