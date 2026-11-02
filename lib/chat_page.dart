import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
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
import 'cron_page.dart';
import 'git_page.dart';
import 'image_sheet.dart';
import 'hermes.dart';
import 'kanban_page.dart';
import 'mac.dart';
import 'l10n/app_localizations.dart';
import 'memory_page.dart';
import 'model_sheet.dart';
import 'quota_page.dart';
import 'screen_page.dart';
import 'tools_page.dart';
import 'voice.dart';
import 'settings.dart';
import 'system_page.dart';
import 'vault_page.dart';

part 'chat_composer.dart';
part 'chat_messages.dart';
part 'chat_sidebar.dart';

class Chat {
  Chat({this.stored = '', this.name = ''}) : loaded = stored.isEmpty;
  final msgs = <Msg>[];
  String model = settings.model;
  late String effort = stored.isEmpty ? settings.effort : ''; // a reopened chat keeps the effort it ran with
  String stored; // server session id, '' until the first message creates it
  String name; // server title
  bool pinned = false; // kept at the top of the menu, on every device
  DateTime? active; // last activity, for the menu's date groups; null = new here, now
  bool loaded; // transcript fetched (always for a chat started here)
  bool loading = false;
  double? context; // share of the context window the server reports, null until known
  double cost = 0; // USD spent on it so far, as the server counts it
  // runtime session on the current gateway connection, and the model it runs
  Gateway? on;
  String live = '';
  String applied = '';
  Future<void>? warming; // the resume [open] started
  // its running turn, which goes on while another chat is open
  StreamSubscription<GatewayEvent>? sub;
  bool streaming = false;
  final queue = <Msg>[]; // sent while Hermes answers, each sent once the reply before it is done
  String phase = ''; // what the running turn does: '' thinks, 'writing', else the tool it runs
  DateTime since = DateTime.now(); // when the running turn started
  // this computer, for the commands its replies ask to run
  final shell = MacShell();
  // ponytail: told again once per app launch, as the transcript doesn't say whether compressions kept it
  bool macTold = false; // the instructions went in since the app opened, and no compression since
  bool macTrusted = false; // "always in this chat": what isn't risky runs unasked
  int compressions = 0;
  // the folder it works in, picked in the app: on the server, or here through [shell]
  String folder = '';
  bool folderHere = false;
  String get title => name.isNotEmpty ? name : msgs.firstOrNull?.text ?? ''; // only titled chats are listed

  /// Works in [path] from now on, which Hermes is told with the next message.
  void workIn(String path, {required bool here}) {
    folder = path;
    folderHere = here;
    macTold = false;
    if (here) {
      shell
        ..stop() // idle: the next step starts a shell there
        ..cwd = path;
    }
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  var chats = [Chat()];
  late Chat chat = chats.first;
  final input = TextEditingController();
  late final focus = FocusNode(onKeyEvent: enterKey);
  final searchFocus = FocusNode();
  final scroll = ScrollController();
  final models = ValueNotifier<Models>((list: const [], loading: false, error: null));
  late final AnimationController drawer;
  Msg? fresh; // latest user message, animated on arrival
  Msg? editing; // a sent message the composer rewrites, to send in its place
  bool atBottom = true;
  String query = '';
  List<Found> found = []; // conversations whose messages match [query]
  final pending = <Attachment>[]; // photos and files for the next message
  bool dragging = false; // files held over the window
  final pane = GlobalKey<NavigatorState>();
  final paneRefresh = ValueNotifier(0);
  List<Slash> slashes = []; // skills matching the `/` being typed
  String slashFor = '';
  Chat? bot; // the server's Bot Chat, where scheduled jobs deliver their results
  bool get streaming => chat.streaming;
  List<Msg> get queue => chat.queue;
  String get phase => chat.phase;
  DateTime get since => chat.since;

  @override
  void initState() {
    super.initState();
    // made now: first touched in dispose (a wide window never opens it), it would look up a gone ticker
    drawer = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
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
    // a new question from outside: the Mac's global shortcut (⌥Space), or Siri and Shortcuts with the question itself
    const quick = MethodChannel('herapp/quick');
    quick.setMethodCallHandler((call) async {
      if (call.method == 'ask') ask(call.arguments is String ? call.arguments as String : '');
      if (call.method == 'continue') continueChat(call.arguments);
    });
    quick.invokeListMethod<String>('ready').then((asked) => asked?.forEach(ask)).catchError((Object _) {}); // only iPhone queues them
    quick.invokeMethod<Object?>('continued').then(continueChat).catchError((Object _) {}); // handed over before the app was up
    WidgetsBinding.instance.addObserver(this);
    takeShared();
  }

  /// Lists the server's stored conversations in the sidebar, after the chats not saved there yet.
  Future<void> loadSessions() async {
    try {
      final g = await gateway();
      if (g == null) return;
      final rows = parseSessions(await g.call('session.list', {'limit': 50}));
      // only the REST list tells which are pinned (those older than the 50 too) and when each was last active
      final rest = {
        for (final r in await serverApi(
          'GET',
          '/api/sessions',
          query: {'limit': '100', 'archived': 'exclude', 'order': 'recent'},
        ).then((b) => parseSessions(jsonDecode(b ?? '{}') as Map), onError: (Object _) => const <Session>[]))
          r.id: r,
      };
      // hidden from the list, the Bot Chat is found by its name (an older server ignores the title and lists all)
      final canonical = switch (await g.call('session.list', {'title': 'Bot Chat'}).catchError((Object _) => const {})) {
        {'sessions': [{'title': 'Bot Chat'} && final Map s, ...]} => '${s['resolved_id'] ?? s['id']}',
        _ => '',
      };
      if (!mounted) return;
      final known = {
        for (final c in [...chats, ?bot]) c.stored: c,
      };
      setState(() {
        bot = canonical.isEmpty ? null : known[canonical] ?? Chat(stored: canonical, name: 'Bot Chat');
        chats = [
          ...chats.where((c) => c.stored.isEmpty),
          for (final r in [
            ...rows,
            for (final r in rest.values)
              if (r.pinned && !rows.any((row) => row.id == r.id)) r,
          ])
            ((known[r.id]?..name = r.title) ?? Chat(stored: r.id, name: r.title))
              ..pinned = rest[r.id]?.pinned ?? false
              ..active = rest[r.id]?.at ?? r.at,
          // the server's list is the truth; only the open chat, or one still answering, stays if it's missing from it
          for (final c in {...chats, chat})
            if (c.stored.isNotEmpty && !identical(c, bot) && (identical(c, chat) || c.streaming) && !rows.any((r) => r.id == c.stored)) c,
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
      if (created && c.folder.isNotEmpty && !c.folderHere) {
        c.folder = '${(await g.call('session.cwd.set', {'session_id': c.live, 'cwd': c.folder}))['cwd'] ?? c.folder}';
      }
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
      final warming = c.warming = warm(g, c);
      try {
        final body = await serverApi('GET', '/api/sessions/${Uri.encodeComponent(c.stored)}/messages');
        c
          ..msgs.clear()
          ..msgs.addAll(transcript((jsonDecode(body ?? '{}') as Map)['messages']))
          ..loaded = true;
        loadCost(c);
      } finally {
        // the running turn goes after the transcript, which may already hold its question
        if (await warming case (:final asked, :final reply) when c.streaming || reply.text.isNotEmpty) {
          if (asked.isNotEmpty && c.msgs.lastWhere((m) => m.user, orElse: () => Msg(true, '')).text.trim() != asked) {
            c.msgs.add(Msg(true, asked));
          }
          c.msgs.add(reply);
        }
      }
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
  /// A turn still running (sent from elsewhere, or before the app was closed) streams on into the reply it
  /// returns, with the question it answers, for [open] to show after the transcript.
  Future<({String asked, Msg reply})?> warm(Gateway g, Chat c) async {
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
      g.call('subagent.list', {'session_id': c.live}).then((r) {
        for (final a in (r['subagents'] as List? ?? const []).whereType<Map>()) {
          trackSubagent('', c.live, a); // still working since before the app opened
        }
      }).ignore();
      g.call('session.context_breakdown', {'session_id': c.live}).then((b) {
        if (b['context_max'] case final num max when max > 0 && c.context == null && mounted) setState(() => c.context = contextOf(b));
      }).ignore();
      // `running` outlasts the reply while the server wraps up (title, memory): its turn is over once `inflight` is cleared
      final inflight = r['inflight'];
      if (r['running'] != true || inflight is! Map || inflight['error'] != null || c.streaming || !mounted) return null;
      final reply = Msg(false, '${inflight['assistant'] ?? ''}');
      setState(() {
        c.streaming = true;
        c.phase = reply.text.isEmpty ? '' : 'writing';
        c.since = switch (r['turn_started_at']) {
          final num t => DateTime.fromMillisecondsSinceEpoch((t * 1000).round()),
          _ => DateTime.now(),
        };
      });
      follow(g, c, c.live, reply);
      return (asked: withoutMacNote('${inflight['user'] ?? ''}').trim(), reply: reply);
    } catch (e) {
      debugPrint('Warm: $e');
      return null;
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

  /// Dictates into the composer, after what is already typed; again, stops.
  Future<void> dictate() async {
    if (voice.listening) return voice.stopDictating();
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    settings.haptic();
    final before = input.text.trimRight();
    final ok = await voice.dictate((words) {
      final text = before.isEmpty || words.isEmpty ? '$before$words' : '$before $words';
      input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(l.voiceUnavailable)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [...chats, ?bot]) {
      c.sub?.cancel();
      c.shell.stop();
    }
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

  // the share extension opens the app: what it left waits in its inbox
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) takeShared();
  }

  /// Starts a new chat with what was shared from other apps (iPhone's "Share → Hermes"), to send once looked over.
  Future<void> takeShared() async {
    try {
      final shares = await const MethodChannel('herapp/quick').invokeListMethod<Map>('shared') ?? [];
      if (shares.isEmpty || !mounted) return;
      ask('');
      input.text = [for (final s in shares) '${s['text'] ?? ''}'.trim()].where((t) => t.isNotEmpty).join('\n\n');
      for (final s in shares) {
        for (final f in (s['files'] as List? ?? const []).cast<Map>()) {
          final name = '${f['name']}';
          final image = RegExp(r'\.(png|jpe?g|gif|webp|heic)$', caseSensitive: false).hasMatch(name);
          setState(() => pending.add((name: name, bytes: f['bytes'] as Uint8List, image: image)));
        }
      }
    } on MissingPluginException {
      // only the iPhone app has a share extension
    } catch (e) {
      debugPrint('Shared: $e');
    }
  }

  String offered = ''; // the conversation Handoff offers the user's other Apple devices

  /// Offers the open conversation to the user's other Apple devices, once the server stores it.
  void handOff() {
    if (chat.stored == offered) return;
    offered = chat.stored;
    final it = offered.isEmpty ? null : {'session': offered, 'title': chat.title, 'server': settings.url};
    const MethodChannel('herapp/quick').invokeMethod<void>('handoff', it).catchError((Object _) {}); // Apple only
  }

  /// Opens the conversation another device handed over, if it is on this app's server.
  void continueChat(Object? handed) {
    String bare(Object? url) => '$url'.replaceFirst(RegExp(r'/+$'), '');
    if (!mounted) return;
    if (handed case {'session': final String id} when id.isNotEmpty && bare(handed['server']) == bare(settings.url)) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      openFound((id: id, title: '${handed['title'] ?? ''}', snippet: ''));
    }
  }

  /// Opens a new chat on top of everything, sending [question] when there is one, else waiting for it.
  void ask(String question) {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    newChat();
    if (question.trim().isEmpty) return focus.requestFocus();
    input.text = question;
    send();
  }

  void send() {
    final text = input.text.trim();
    if (text.isEmpty && pending.isEmpty) return;
    settings.haptic();
    input.clear();
    final m = Msg(true, text, null, [...pending]);
    if (editing case final old? when !streaming && chat.msgs.contains(old)) {
      setState(() {
        pending.clear();
        editing = null;
      });
      return resend(old, m);
    }
    editing = null;
    final later = streaming; // Hermes is still answering: it goes once the reply is done
    setState(() {
      pending.clear();
      (later ? queue : chat.msgs).add(m);
      fresh = m;
    });
    if (!later) respond();
  }

  /// Takes [msgs] off the queue and back into the composer, to edit or send again.
  void unqueue(List<Msg> msgs) => setState(() {
    queue.removeWhere(msgs.contains);
    input.text = [for (final m in msgs) m.text, input.text].where((t) => t.trim().isNotEmpty).join('\n\n');
    pending.insertAll(0, [for (final m in msgs) ...m.files]);
  });

  /// What the running turn does, for the header.
  String status(AppLocalizations l) => switch (phase) {
    '' => l.statusThinking,
    'writing' => l.statusWriting,
    final tool => l.statusTool(tool),
  };

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
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, 'image'), child: Text(l.imageCreate)),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
      ),
    );
    if (from == 'image') {
      if (!mounted) return;
      final made = await showPanel<Attachment>(context, (_) => const ImageSheet(), scrollControlled: true);
      if (made != null) setState(() => pending.add(made));
      return;
    }
    try {
      final picked = switch (from) {
        'photos' => [for (final x in await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2048)) (x, true)],
        'camera' => [
          if (await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2048) case final x?) (x, true),
        ],
        'files' => [for (final x in await openFiles()) (x, false)],
        _ => const <(XFile, bool)>[],
      };
      await addFiles(picked);
    } catch (e) {
      debugPrint('Attach: $e');
    }
  }

  /// Queues [picked] for the next message; a file named like a picture goes as one.
  Future<void> addFiles(Iterable<(XFile, bool)> picked) async {
    for (final (x, image) in picked) {
      final bytes = await x.readAsBytes();
      final looksImage = image || RegExp(r'\.(png|jpe?g|gif|webp|heic)$', caseSensitive: false).hasMatch(x.name);
      if (mounted) setState(() => pending.add((name: x.name, bytes: bytes, image: looksImage)));
    }
  }

  /// Sends the last user message to Hermes and streams the reply in; [again] replaces the previous reply,
  /// [queued] waits for a turn the server may still be closing.
  Future<void> respond({Chat? of, bool again = false, bool queued = false}) async {
    final c = of ?? chat;
    final asked = c.msgs.last;
    var prompt = asked.text;
    final turn = c.msgs.where((m) => m.user).length - 1; // the server's user-turn ordinal
    final reply = Msg(false, '');
    setState(() {
      c.msgs.add(reply);
      c.streaming = true;
      c.phase = '';
      c.since = c.active = DateTime.now();
    });
    if (identical(c, chat)) toBottom();
    void fail(Object? e) => failTurn(c, reply, e);

    try {
      final g = await gateway();
      if (g == null) return fail(null); // no server set
      final sid = await attach(g, c);
      if (!c.streaming) return;
      follow(g, c, sid, reply);
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
        // a PDF's pages also go as pictures, for the model to see them (the server needs poppler's pdftoppm)
        if (f.name.toLowerCase().endsWith('.pdf')) {
          try {
            await g.call('pdf.attach', {'session_id': sid, 'content_base64': base64Encode(f.bytes!), 'filename': f.name});
          } catch (e) {
            debugPrint('PDF pages: $e'); // read through its file only
          }
        }
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
            return stop(of: c);
          }
        } on HttpException catch (e) {
          debugPrint('Dispatch: ${e.message}'); // not a skill: sent as typed
        }
        if (!c.streaming) return;
      }
      // what this computer can do for the chat goes before the user's words, which still title it
      final told = macOn && !c.macTold;
      if (told) {
        prompt = '${c.shell.note(settings.macToken, folder: c.folder, here: c.folderHere)}\n\n$prompt';
        if (typed.isEmpty) typed = asked.text;
      }
      await g.call('prompt.submit', {
        'session_id': sid,
        'text': prompt,
        if (typed.isNotEmpty) 'title_preview': typed,
        if (again) ...{'truncate_before_user_ordinal': turn, 'confirm_truncate': true},
        if (queued) 'queued': true,
      });
      if (told) c.macTold = true;
    } catch (e) {
      debugPrint('Chat: $e');
      fail(e);
    }
  }

  /// Streams the turn [c] runs as [sid] on [g] into [reply], until it completes.
  void follow(Gateway g, Chat c, String sid, Msg reply) {
    c.sub = g.events.listen((e) {
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
          setState(() {
            reply.text += e.payload['text'] as String;
            c.phase = 'writing';
          });
          if (atBottom && identical(c, chat)) toBottom(jump: true);
        case 'tool.start':
          final p = e.payload;
          setState(() {
            reply.tools.add(
              Tool(
                '${p['tool_id']}',
                '${p['name']}',
                '${p['context'] ?? p['preview'] ?? ''}',
                args: p['args'] is Map ? p['args'] as Map : const {},
              ),
            );
            c.phase = '${p['name']}';
          });
        case 'tool.complete':
          setState(() {
            for (final t in reply.tools.where((t) => t.id == '${e.payload['tool_id']}')) {
              t.done = true;
              if (t.name == 'memory' && !memorySaved(e.payload['result'])) t.args = const {}; // no card for a refused write
            }
            c.phase = '';
          });
        case 'request.cancel' when reply.ask?.id == e.payload['id']:
          setState(() => reply.ask = null);
        case 'session.usage':
          compressed(c, e.payload['usage']);
          setState(() => c.context = contextOf(e.payload['usage']) ?? c.context);
        case 'message.complete':
          final p = e.payload;
          compressed(c, p['usage']);
          c.context = contextOf(p['usage']) ?? c.context;
          if (reply.text.trim().isEmpty && p['text'] is String) reply.text = p['text'] as String;
          if (p['status'] == 'error') return failTurn(c, reply, '${p['error'] ?? p['failure_reason'] ?? 'error'}');
          c.streaming = false; // over: nothing left to interrupt
          stop(of: c, next: true);
          if (macOn) runMac(c, reply);
        case 'error':
          failTurn(c, reply, '${e.payload['message']}');
      }
    }, onDone: () => failTurn(c, reply, const HttpException('connection to Hermes lost')));
  }

  bool get macOn => settings.macShell && macCapable;

  /// A compression may have summed up the instructions [macNote] gave: they go again with the next message.
  void compressed(Chat c, Object? usage) {
    if (usage case {'compressions': final int n} when n > c.compressions) {
      c
        ..compressions = n
        ..macTold = false;
    }
  }

  /// Takes the steps [reply] asks of this computer in order, asking the user first for those that need it
  /// (a refusal skips the rest), then hands Hermes what they did.
  Future<void> runMac(Chat c, Msg reply) async {
    final steps = macSteps(reply.text, settings.macToken);
    if (steps.isEmpty) return;
    setState(() => reply.mac = [for (final s in steps) MacRun(s)]);
    var refused = false;
    for (final r in reply.mac) {
      if (refused) {
        setState(() => r.state = 'skipped');
        continue;
      }
      if (macAsks(r.step, trusted: c.macTrusted, home: MacShell.home, cwd: c.shell.cwd)) {
        final decision = r.decision = Completer<bool>();
        setState(() => r.state = 'ask');
        settings.haptic();
        final run = await decision.future;
        if (!mounted) return;
        if (!run) {
          refused = true;
          setState(() => r.state = 'refused');
          continue;
        }
      }
      setState(() => r.state = 'running');
      final (code, out) = r.step.path.isEmpty
          ? await c.shell.run(r.step.script, (o) => mounted ? setState(() => r.out = o) : null)
          : c.shell.write(r.step.path, r.step.content);
      if (!mounted) return;
      setState(() {
        r
          ..code = code
          ..out = out
          ..state = 'done';
      });
    }
    // the reply was redone or deleted meanwhile: its results answer nothing
    if (!mounted || !c.msgs.contains(reply)) return;
    final m = Msg(true, macResult(reply.mac));
    if (c.streaming) return setState(() => c.queue.insert(0, m));
    setState(() => c.msgs.add(m));
    respond(of: c);
  }

  /// The user's answer to the step [r] waits on: run it ([always] trusts the chat from now on), or not.
  void decide(MacRun r, bool run, {bool always = false}) {
    settings.haptic();
    if (always) chat.macTrusted = true;
    r.decision?.complete(run);
    r.decision = null;
  }

  /// Ends [c]'s turn on the error [e] (a message, or what the server raised), under what [reply] already says.
  void failTurn(Chat c, Msg reply, Object? e) {
    if (!c.streaming) return;
    reply.text += '${reply.text.isEmpty ? '' : '\n\n'}⚠️ ${e is String ? e : serverErrorText(AppLocalizations.of(context), e)}';
    stop(of: c);
  }

  /// Ends the turn of [of] (the open chat by default); [next] sends the first queued message, else the
  /// queue goes back to the composer (once the chat is open again, when it isn't).
  void stop({Chat? of, bool next = false}) {
    final c = of ?? chat;
    final g = c.on;
    if (c.streaming && g != null && !g.closed && c.live.isNotEmpty) g.call('session.interrupt', {'session_id': c.live}).ignore();
    c.sub?.cancel();
    c.sub = null;
    if (c.msgs.lastOrNull case final m? when !m.user) {
      m.ask = null; // an interrupted turn drops its question
      if (m.text.isEmpty && m.tools.isEmpty) c.msgs.removeLast();
    }
    setState(() => c.streaming = false);
    loadSessions(); // a first message adds the chat to the server's list
    if (c.stored.isNotEmpty) loadCost(c);
    if (c.queue.isEmpty) return;
    // the turn it waited for failed or was left: nothing is lost (tapped back into the composer when away)
    if (!next) return identical(c, chat) ? unqueue([...c.queue]) : null;
    setState(() => c.msgs.add(c.queue.removeAt(0)));
    respond(of: c, queued: true);
  }

  /// Sends the user's [choice] for the command [m] is waiting on.
  void answer(Msg m, String choice) {
    final ask = m.ask;
    if (ask == null) return;
    settings.haptic();
    chat.on?.reply(ask.id, {'choice': choice});
    setState(() => m.ask = null);
  }

  void regenerate() => resend(chat.msgs.lastWhere((m) => m.user));

  /// Sends the chat again from the user message [asked], or from [edited] in its place; what followed is dropped.
  void resend(Msg asked, [Msg? edited]) {
    stop();
    setState(() {
      chat.msgs.removeRange(chat.msgs.indexOf(asked) + (edited == null ? 1 : 0), chat.msgs.length);
      if (edited != null) chat.msgs.add(fresh = edited);
    });
    respond(again: true);
  }

  /// Puts the sent message [m] back in the composer, to rewrite and send in its place.
  void edit(Msg m) {
    setState(() {
      editing = m;
      input.text = m.text;
      pending
        ..clear()
        ..addAll(m.files);
    });
    focus.requestFocus();
  }

  void cancelEdit() => setState(() {
    editing = null;
    input.clear();
    pending.clear();
  });

  void newChat() {
    final was = chat; // a new chat works where the last one did
    if (chat.msgs.isNotEmpty) chats.insert(0, chat = Chat()..workIn(was.folder, here: was.folderHere));
    setState(() {});
    closeDrawer();
  }

  /// Picks the folder [chat] works in: on this computer (which then runs its commands), or on the server.
  Future<void> pickFolder() async {
    final l = AppLocalizations.of(context);
    final c = chat;
    final picked = await showPageSheet<(String, bool)>(
      context,
      (_) => _Folders(folder: c.folder, here: macCapable && (c.folder.isEmpty || c.folderHere), server: serverFolders),
    );
    if (picked == null || !mounted) return;
    var (path, here) = picked;
    if (!here && c.stored.isNotEmpty) {
      // a chat not sent yet moves once its session is created
      final messenger = ScaffoldMessenger.of(context);
      try {
        if (await gateway() case final g?) {
          path = '${(await g.call('session.workspace.move', {'session_key': c.stored, 'cwd': path}))['cwd'] ?? path}';
        }
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(l.folderFailed(e is HttpException ? e.message : '$e'))));
        return;
      }
    }
    if (here) settings.macShell = true; // working here is Hermes running commands here
    if (mounted) setState(() => c.workIn(path, here: here));
  }

  /// The server's folders in what [path] names, those starting with its last part.
  Future<List<String>> serverFolders(String path) async {
    final g = await gateway();
    if (g == null) return const [];
    // ponytail: the server lists 30 entries (no build dirs), hidden ones first: asked again without them;
    // typing a name's start finds the rest
    final found = await Future.wait([
      g.call('complete.path', {'word': '@$path'}),
      g.call('complete.path', {'word': '@folder:$path'}),
    ]);
    return {
      for (final r in found)
        for (final i in (r['items'] is List ? r['items'] as List : const []).whereType<Map>())
          if (i['display'] case final String d when d.endsWith('/')) d.substring(0, d.length - 1),
    }.toList();
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
      if (c.streaming) stop(of: c);
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

  /// Pins [c] at the top of the menu, or unpins it.
  Future<void> pin(Chat c, bool on) async {
    final id = Uri.encodeComponent(c.stored);
    try {
      // the server takes a change only against the session's current revision
      final snap = jsonDecode(await serverApi('GET', '/api/sessions/$id/mutation-snapshot') ?? '{}') as Map;
      await serverApi(
        'PATCH',
        '/api/sessions/$id',
        body: {
          'request_id': 'herapp-${DateTime.now().microsecondsSinceEpoch}',
          'expected_revision': snap['runtime_revision'] ?? 0,
          'pinned': on,
        },
      );
      setState(() => c.pinned = on);
    } catch (e) {
      failed(e);
    }
  }

  /// Archives [c] (or brings it back): out of the menu, kept on the server with its messages.
  Future<bool> archive(String stored, {bool on = true}) async {
    try {
      final g = await gateway();
      if (g == null) throw const HttpException('no server');
      await g.call('session.archive', {'session_id': stored, 'archived': on});
      return true;
    } catch (e) {
      failed(e);
      return false;
    }
  }

  void failed(Object e) {
    debugPrint('Chat: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.chatActionFailed(e is HttpException ? e.message : '$e'))));
    }
  }

  /// What can be done to [c] from the menu: pin, archive, delete.
  Future<void> chatMenu(Chat c) async {
    final action = await showChoices<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, 'pin'), child: Text(c.pinned ? l.chatUnpin : l.chatPin)),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(context, 'archive'), child: Text(l.chatArchive)),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'delete'),
            child: Text(l.deleteChat),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
      ),
    );
    switch (action) {
      case 'pin':
        await pin(c, !c.pinned);
      case 'archive' when await archive(c.stored):
        deleted(c);
      case 'delete' when await confirmDelete(c):
        deleted(c);
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
    setState(() => chat = c);
    closeDrawer();
    // the Bot Chat also fills up while away, from the scheduled jobs
    if ((!c.loaded || identical(c, bot)) && !c.loading && !c.streaming) open(c);
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

  AppLocalizations get l => AppLocalizations.of(context);

  /// The menu's pages, in order; ⌘1… opens them.
  List<(String, IconData, Widget)> pages(AppLocalizations l) => [
    (l.quotas, CupertinoIcons.gauge, const QuotaPage()),
    (l.agents, CupertinoIcons.sparkles, const AgentsPage()),
    (l.kanban, CupertinoIcons.square_split_2x1, const KanbanPage()),
    (l.memory, CupertinoIcons.lightbulb, const MemoryPage()),
    (l.vault, CupertinoIcons.lock_shield, const VaultPage()),
    (l.system, CupertinoIcons.desktopcomputer, const SystemPage()),
    (l.screen, CupertinoIcons.macwindow, const ScreenPage()),
    (l.tools, CupertinoIcons.hammer, const ToolsPage()),
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
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
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
    handOff();
  }

  void toBottom({bool jump = false}) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!scroll.hasClients) return;
    // a jump would cancel the user's drag or fling, before it gets far enough to stop following the reply
    if (jump && scroll.position.isScrollingNotifier.value) return;
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
    final width = math.min(screen * .82, 360.0); // a phone's menu, at most a sidebar's width on a narrow window
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
                        Positioned(
                          left: x - width,
                          top: 0,
                          bottom: 0,
                          width: width,
                          // out of sight, its animations (a chat's answering dot) stand still
                          child: TickerMode(enabled: drawer.value > 0, child: sidebar),
                        ),
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

  Widget _main(ColorScheme c) {
    final main = ColoredBox(
      color: c.surface,
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  if (wide) const SizedBox(width: 52) else _IconBtn(label: l.a11yMenu, onTap: openDrawer, child: _MenuIcon(c.onSurface)),
                  Expanded(
                    // empty: no title, the centered pill is the picker
                    child: chat.msgs.isEmpty
                        ? const SizedBox()
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Herapp',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: streaming
                                    ? _Elapsed(
                                        status(AppLocalizations.of(context)),
                                        since,
                                        style: TextStyle(fontSize: 17, color: c.outline),
                                      )
                                    : Text(
                                        modelName(chat.model),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 17, color: c.outline),
                                      ),
                              ),
                            ],
                          ),
                  ),
                  // a wide window has it in the menu beside: the same room, for the title to stay centered
                  if (wide)
                    const SizedBox(width: 52)
                  else
                    _IconBtn(
                      label: l.newChat,
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
                            Hover(
                              radius: 20,
                              child: GestureDetector(
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
                              itemCount: chat.msgs.length + queue.length,
                              itemBuilder: (_, i) => i < chat.msgs.length
                                  ? _message(c, chat.msgs[i], i == chat.msgs.length - 1)
                                  : _queued(c, queue[i - chat.msgs.length]),
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
                              child: Hover(
                                radius: 999,
                                label: l.a11yToBottom,
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
                        ),
                      ],
                    ),
            ),
            readable(_composer(c), width: 792),
          ],
        ),
      ),
    );
    if (!const [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux].contains(defaultTargetPlatform)) return main;
    // files dropped on the chat join the next message
    return DropTarget(
      onDragEntered: (_) => setState(() => dragging = true),
      onDragExited: (_) => setState(() => dragging = false),
      onDragDone: (d) async {
        setState(() => dragging = false);
        for (final x in d.files.where((x) => x is! DropItemDirectory)) {
          // the sandbox opens a file from outside the app only while its bookmark is held
          final bookmark = x.extraAppleBookmark ?? Uint8List(0);
          final held = await DesktopDrop.instance.startAccessingSecurityScopedResource(bookmark: bookmark);
          try {
            await addFiles([(x, false)]);
          } catch (e) {
            debugPrint('Drop: $e');
          } finally {
            if (held) DesktopDrop.instance.stopAccessingSecurityScopedResource(bookmark: bookmark).ignore();
          }
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          main,
          if (dragging)
            IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface.withValues(alpha: .85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.outline, width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.paperclip, size: 40, color: c.onSurface),
                    const SizedBox(height: 12),
                    Text(AppLocalizations.of(context).dropFiles, style: TextStyle(fontSize: 17, color: c.onSurface)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.label, required this.onTap, required this.child, this.small = false});
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool small;

  @override
  Widget build(BuildContext context) => Hover(
    radius: 12,
    label: label,
    child: CupertinoButton(padding: EdgeInsets.all(small ? 6 : 14), onPressed: onTap, child: child),
  );
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

/// [label] and the time since [since] (m:ss), ticking each second.
class _Elapsed extends StatefulWidget {
  const _Elapsed(this.label, this.since, {required this.style});
  final String label;
  final DateTime since;
  final TextStyle style;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  late final Timer tick;

  @override
  void initState() {
    super.initState();
    tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = DateTime.now().difference(widget.since).inSeconds;
    return Text(
      '${widget.label} ${s ~/ 60}:${'${s % 60}'.padLeft(2, '0')}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: widget.style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}
