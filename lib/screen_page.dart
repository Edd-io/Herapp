import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cron_page.dart';
import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';

/// A VNC client (RFB 3.8, no security: the dashboard's ticket is the gate) for the bot's screen; [pixels]
/// holds the screen as RGBA, [onFrame] runs after each update.
// ponytail: raw and copy-rect encodings only (a full screen is ~5 MB); add ZRLE/Tight if it crawls on mobile data
class Rfb {
  Rfb(Stream<List<int>> input, this._send) {
    input.listen(
      (d) {
        final chunk = d is Uint8List ? d : Uint8List.fromList(d);
        _chunks.add(chunk);
        _have += chunk.length;
        _more?.complete();
        _more = null;
      },
      onDone: _end,
      onError: (Object _) => _end(),
    );
  }

  final void Function(List<int>) _send;
  final _chunks = Queue<Uint8List>();
  var _have = 0, _off = 0;
  var _closed = false;
  Completer<void>? _more;
  int width = 0, height = 0;
  Uint8List pixels = Uint8List(0);
  VoidCallback? onFrame;

  void _end() {
    _closed = true;
    _more?.complete();
    _more = null;
  }

  Future<Uint8List> _read(int n) async {
    while (_have < n) {
      if (_closed) throw const SocketException('screen connection closed');
      await (_more ??= Completer<void>()).future;
    }
    final out = Uint8List(n);
    for (var i = 0; i < n;) {
      final c = _chunks.first;
      final take = min(n - i, c.length - _off);
      out.setRange(i, i + take, c, _off);
      i += take;
      _off += take;
      if (_off == c.length) {
        _chunks.removeFirst();
        _off = 0;
      }
    }
    _have -= n;
    return out;
  }

  Future<ByteData> _data(int n) async => ByteData.sublistView(await _read(n));

  void _resize(int w, int h) {
    width = w;
    height = h;
    pixels = Uint8List(w * h * 4);
  }

  void _request({bool incremental = true}) =>
      _send([3, incremental ? 1 : 0, 0, 0, 0, 0, width >> 8, width & 255, height >> 8, height & 255]);

  /// Speaks RFB until the connection ends; throws on what it can't read.
  Future<void> run() async {
    await _read(12);
    _send(ascii.encode('RFB 003.008\n'));
    final types = await _read((await _read(1))[0]);
    if (!types.contains(1)) throw SocketException('screen refused: ${utf8.decode(await _read((await _data(4)).getUint32(0)))}');
    _send(const [1]);
    if ((await _data(4)).getUint32(0) != 0) throw const SocketException('screen refused the connection');
    _send(const [1]); // shared: the agent's own viewer stays on
    final init = await _data(24);
    _resize(init.getUint16(0), init.getUint16(2));
    await _read(init.getUint32(20)); // the desktop's name
    // 32 bits, little-endian true colour, red in the low byte: R, G, B, (pad) in memory, as RGBA
    _send(const [0, 0, 0, 0, 32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 0, 8, 16, 0, 0, 0]);
    final encodings = [0, 1, -223]; // raw, copy-rect, desktop size
    _send([
      2,
      0,
      0,
      encodings.length,
      for (final e in encodings) ...[(e >> 24) & 255, (e >> 16) & 255, (e >> 8) & 255, e & 255],
    ]);
    _request(incremental: false);
    while (true) {
      switch ((await _read(1))[0]) {
        case 0: // framebuffer update
          final rects = (await _data(3)).getUint16(1);
          for (var i = 0; i < rects; i++) {
            final r = await _data(12);
            final x = r.getUint16(0), y = r.getUint16(2), w = r.getUint16(4), h = r.getUint16(6);
            switch (r.getInt32(8)) {
              case 0:
                final raw = await _read(w * h * 4);
                for (var a = 3; a < raw.length; a += 4) {
                  raw[a] = 255;
                }
                for (var row = 0; row < h; row++) {
                  pixels.setRange(((y + row) * width + x) * 4, ((y + row) * width + x + w) * 4, raw, row * w * 4);
                }
              case 1:
                final src = await _data(4);
                final sx = src.getUint16(0), sy = src.getUint16(2);
                final rows = [
                  for (var row = 0; row < h; row++)
                    Uint8List.fromList(pixels.sublist(((sy + row) * width + sx) * 4, ((sy + row) * width + sx + w) * 4)),
                ];
                for (final (row, line) in rows.indexed) {
                  pixels.setRange(((y + row) * width + x) * 4, ((y + row) * width + x + w) * 4, line);
                }
              case -223:
                _resize(w, h);
              case final e:
                throw SocketException('screen sent an unknown encoding $e');
            }
          }
          onFrame?.call();
          _request();
        case 1: // colour map: unused in true colour
          await _read((await _data(5)).getUint16(3) * 6);
        case 2: // bell
          break;
        case 3: // the screen's clipboard
          await _read((await _data(7)).getUint32(3));
        case final t:
          throw SocketException('screen sent an unknown message $t');
      }
    }
  }

  /// The mouse at ([x], [y]) on the screen, with [buttons] down (1 left, 2 middle, 4 right, 8/16 wheel up/down).
  void pointer(int x, int y, int buttons) => _send([
    5,
    buttons,
    x.clamp(0, width - 1) >> 8,
    x.clamp(0, width - 1) & 255,
    y.clamp(0, height - 1) >> 8,
    y.clamp(0, height - 1) & 255,
  ]);

  /// The key [keysym] (X11) pressed or released.
  void key(int keysym, bool down) =>
      _send([4, down ? 1 : 0, 0, 0, (keysym >> 24) & 255, (keysym >> 16) & 255, (keysym >> 8) & 255, keysym & 255]);

  /// Types [text], one key per character.
  void type(String text) {
    for (final r in text.runes) {
      key(keysymOf(r), true);
      key(keysymOf(r), false);
    }
  }
}

/// The X11 keysym of the character [rune].
int keysymOf(int rune) => switch (rune) {
  0x0A || 0x0D => 0xff0d,
  0x09 => 0xff09,
  0x08 => 0xff08,
  < 0x100 => rune,
  _ => 0x01000000 | rune,
};

final _keysyms = {
  LogicalKeyboardKey.backspace: 0xff08,
  LogicalKeyboardKey.tab: 0xff09,
  LogicalKeyboardKey.enter: 0xff0d,
  LogicalKeyboardKey.numpadEnter: 0xff0d,
  LogicalKeyboardKey.escape: 0xff1b,
  LogicalKeyboardKey.delete: 0xffff,
  LogicalKeyboardKey.home: 0xff50,
  LogicalKeyboardKey.arrowLeft: 0xff51,
  LogicalKeyboardKey.arrowUp: 0xff52,
  LogicalKeyboardKey.arrowRight: 0xff53,
  LogicalKeyboardKey.arrowDown: 0xff54,
  LogicalKeyboardKey.pageUp: 0xff55,
  LogicalKeyboardKey.pageDown: 0xff56,
  LogicalKeyboardKey.end: 0xff57,
  LogicalKeyboardKey.shiftLeft: 0xffe1,
  LogicalKeyboardKey.shiftRight: 0xffe2,
  LogicalKeyboardKey.controlLeft: 0xffe3,
  LogicalKeyboardKey.controlRight: 0xffe4,
  LogicalKeyboardKey.altLeft: 0xffe9,
  LogicalKeyboardKey.altRight: 0xffea,
  LogicalKeyboardKey.metaLeft: 0xffeb,
  LogicalKeyboardKey.metaRight: 0xffec,
};

/// The bot's own screen on the server (Hermes' Bot Desktop), where its browser runs: watched live, and
/// taken over to solve what the bot can't (a CAPTCHA, a login), then handed back.
class ScreenPage extends StatefulWidget {
  const ScreenPage({super.key});

  @override
  State<ScreenPage> createState() => _ScreenPageState();
}

class _ScreenPageState extends State<ScreenPage> {
  Gateway? g;
  StreamSubscription<GatewayEvent>? events;
  WebSocket? ws;
  Rfb? rfb;
  ui.Image? image;
  var decoding = false, dirty = false;
  String viewer = '', mine = ''; // this viewer's id, and the lease hash it got when it took over
  Map lease = const {};
  String? problem; // why there is no screen
  var busy = false;
  final keys = <PhysicalKeyboardKey, int>{}; // keysyms pressed, to release the same ones
  final typing = TextEditingController();
  final focus = FocusNode();
  var buttons = 0;

  bool get holding => lease['holder'] == 'human' && mine.isNotEmpty && lease['viewer_hash'] == mine;
  bool get touch => const [TargetPlatform.iOS, TargetPlatform.android].contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    connect();
  }

  @override
  void dispose() {
    if (holding) g?.call('display.lease.release', {'viewer_id': viewer}).ignore();
    events?.cancel();
    ws?.close();
    image?.dispose();
    typing.dispose();
    focus.dispose();
    super.dispose();
  }

  /// Starts the screen if needed and opens its stream.
  Future<void> connect() async {
    if (problem != null) setState(() => problem = null);
    try {
      final g = this.g = await gateway();
      if (g == null) throw StateError('no server');
      events ??= g.events.listen((e) {
        if (e.type == 'display.lease' && e.payload['lease'] is Map && mounted) setState(() => lease = e.payload['lease'] as Map);
      });
      var status = await g.call('display.status');
      if (status['installed'] != true) {
        if (mounted) setState(() => problem = AppLocalizations.of(context).screenMissing);
        return;
      }
      if (status['running'] != true) status = await g.call('display.start');
      final seen = await g.call('display.observe', {'viewer_id': viewer});
      viewer = '${seen['viewer_id']}';
      final base = Uri.parse(settings.url);
      final url = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '${seen['path'] ?? '/api/display/ws'}',
        queryParameters: {'display_ticket': '${seen['ticket']}'},
      );
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10); // follows the tunnel's HttpOverrides
      final ws = this.ws = await WebSocket.connect(url.toString(), customClient: client);
      client.close();
      final rfb = this.rfb = Rfb(ws.cast<List<int>>(), ws.add)..onFrame = paint;
      if (!mounted) return;
      setState(() => lease = seen['lease'] is Map ? seen['lease'] as Map : const {});
      try {
        await rfb.run();
      } on SocketException catch (_) {
        if (!identical(this.ws, ws)) return; // reconnected meanwhile
      }
      if (!mounted || !identical(this.ws, ws)) return;
      // control taken by someone else: back as a watcher; anything else ends the stream
      if (ws.closeCode == 4000) return connect();
      setState(() => problem = AppLocalizations.of(context).screenLost);
    } catch (e) {
      debugPrint('Screen: $e');
      if (mounted) setState(() => problem = serverErrorText(AppLocalizations.of(context), e is StateError ? null : e));
    }
  }

  /// Turns the latest pixels into an image, one at a time.
  void paint() {
    final rfb = this.rfb;
    if (rfb == null || rfb.width == 0) return;
    if (decoding) {
      dirty = true;
      return;
    }
    decoding = true;
    ui.decodeImageFromPixels(rfb.pixels, rfb.width, rfb.height, ui.PixelFormat.rgba8888, (img) {
      decoding = false;
      if (!mounted) return img.dispose();
      setState(() {
        image?.dispose();
        image = img;
      });
      if (dirty) {
        dirty = false;
        paint();
      }
    });
  }

  Future<void> takeOver(bool take) async {
    final g = this.g;
    if (g == null || busy) return;
    settings.haptic();
    setState(() => busy = true);
    try {
      final r = await g.call(take ? 'display.lease.acquire' : 'display.lease.release', {'viewer_id': viewer, if (take) 'reason': 'Herapp'});
      final now = r['lease'] is Map ? r['lease'] as Map : const {};
      if (mounted) {
        setState(() {
          lease = now;
          mine = take ? '${now['viewer_hash'] ?? ''}' : '';
        });
      }
      if (take) focus.requestFocus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).screenFailed(e is HttpException ? e.message : '$e'))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  KeyEventResult onKey(FocusNode _, KeyEvent e) {
    final rfb = this.rfb;
    if (rfb == null || !holding) return KeyEventResult.ignored;
    if (e is KeyUpEvent) {
      if (keys.remove(e.physicalKey) case final k?) rfb.key(k, false);
      return KeyEventResult.handled;
    }
    final c = e.character;
    final k =
        _keysyms[e.logicalKey] ??
        (c != null && c.isNotEmpty && c.runes.first >= 0x20 ? keysymOf(c.runes.first) : keysymOf(e.logicalKey.keyId & 0x1fffff));
    keys[e.physicalKey] = k;
    rfb.key(k, true);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final rfb = this.rfb, image = this.image;
    const accent = Color(0xFFFF3B30);
    Widget screen = const Center(child: CupertinoActivityIndicator());
    if (problem != null) {
      screen = Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
        child: Column(
          children: [
            Text(
              problem!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: c.outline),
            ),
            const SizedBox(height: 12),
            CupertinoButton(onPressed: connect, child: Text(l.screenRetry)),
          ],
        ),
      );
    } else if (rfb != null && image != null) {
      screen = Center(
        child: AspectRatio(
          aspectRatio: rfb.width / rfb.height,
          child: LayoutBuilder(
            builder: (context, box) {
              (int, int) at(Offset p) => ((p.dx / box.maxWidth * rfb.width).round(), (p.dy / box.maxHeight * rfb.height).round());
              void mouse(PointerEvent e) {
                if (!holding || e.kind == PointerDeviceKind.touch) return;
                final (x, y) = at(e.localPosition);
                // Flutter's primary/secondary/middle bits are 1/2/4; RFB's left/middle/right are 1/2/4
                buttons = (e.buttons & 1) | (e.buttons & 4 == 0 ? 0 : 2) | (e.buttons & 2 == 0 ? 0 : 4);
                rfb.pointer(x, y, buttons);
              }

              return DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(border: Border.all(color: holding ? accent : c.outline.withValues(alpha: .3), width: 2)),
                child: Listener(
                  onPointerHover: mouse,
                  onPointerMove: mouse,
                  onPointerDown: mouse,
                  onPointerUp: mouse,
                  onPointerSignal: (e) {
                    if (!holding || e is! PointerScrollEvent) return;
                    final (x, y) = at(e.localPosition);
                    final wheel = e.scrollDelta.dy < 0 ? 8 : 16;
                    for (var i = 0; i < max(1, (e.scrollDelta.dy.abs() / 40).round()); i++) {
                      rfb
                        ..pointer(x, y, buttons | wheel)
                        ..pointer(x, y, buttons);
                    }
                  },
                  child: GestureDetector(
                    // a finger taps (a click), as the bot's screen is too small on a phone to drag on
                    onTapUp: (d) {
                      if (!holding || d.kind != PointerDeviceKind.touch) return;
                      final (x, y) = at(d.localPosition);
                      rfb
                        ..pointer(x, y, 0)
                        ..pointer(x, y, 1)
                        ..pointer(x, y, 0);
                    },
                    child: RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                  ),
                ),
              );
            },
          ),
        ),
      );
      if (touch) screen = InteractiveViewer(maxScale: 6, child: screen);
    }
    return PageFrame(
      title: l.screen,
      full: true,
      action: rfb == null || problem != null
          ? null
          : TextButton(
              onPressed: busy ? null : () => takeOver(!holding),
              child: Text(holding ? l.screenHandBack : l.screenTakeOver, style: TextStyle(color: holding ? accent : c.primary)),
            ),
      child: Focus(
        focusNode: focus,
        autofocus: true,
        onKeyEvent: onKey,
        child: Column(
          children: [
            if (rfb != null && problem == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  holding
                      ? l.screenYours
                      : lease['holder'] == 'human'
                      ? l.screenSomeone
                      : l.screenBot,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: holding ? accent : c.outline),
                ),
              ),
            Expanded(
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: screen),
            ),
            if (holding && touch)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: CupertinoTextField(
                    controller: typing,
                    placeholder: l.screenType,
                    autocorrect: false,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (text) {
                      rfb
                        ?..type(text)
                        ..type('\n');
                      typing.clear();
                    },
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
