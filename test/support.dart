import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/hermes.dart';
import 'package:herapp/model_sheet.dart';
import 'package:herapp/settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a [fakeServer] call receives: the method, its params, and [emit] to push an event later.
/// An answer to a server request arrives as method 'reply' with the whole frame; emitting
/// `'request:method'` sends that server request (id 'r1') instead of an event.
typedef Handler = Object? Function(String method, Map params, void Function(String type, Map payload) emit);

/// Points the app at a fake Hermes gateway answering with [handle]; returns the calls it got.
List<(String, Map)> fakeServer(Handler handle) {
  final calls = <(String, Map)>[];
  settings.url = 'https://hermes.test';
  connectGateway = (base, {user, password}) async {
    final frames = StreamController<String>();
    return Gateway(frames.stream, (out) {
      final j = jsonDecode(out) as Map;
      final method = j['method'] as String? ?? 'reply';
      calls.add((method, j['params'] as Map? ?? j));
      void emit(String type, Map payload) => Timer(
        const Duration(milliseconds: 50),
        () => frames.add(
          jsonEncode(
            type.startsWith('request:')
                ? {
                    'jsonrpc': '2.0',
                    'id': 'r1',
                    'method': type.substring(8),
                    'params': {...payload, 'session_id': 'rt'},
                  }
                : {
                    'jsonrpc': '2.0',
                    'method': 'event',
                    'params': {'type': type, 'session_id': 'rt', 'payload': payload},
                  },
          ),
        ),
      );
      final result = handle(method, j['params'] as Map? ?? j, emit) ?? {};
      if (method == 'reply') return;
      scheduleMicrotask(() => frames.add(jsonEncode({'jsonrpc': '2.0', 'id': j['id'], 'result': result})));
    }, frames.close);
  };
  return calls;
}

/// A server with no history that streams "Hello there" to every prompt.
Object? replies(String method, Map params, void Function(String, Map) emit) {
  switch (method) {
    case 'session.create':
      return {'session_id': 'rt', 'stored_session_id': 's1'};
    case 'prompt.submit':
      emit('message.delta', {'text': 'Hello '});
      emit('message.delta', {'text': 'there'});
      emit('message.complete', {
        'text': 'Hello there',
        'status': 'complete',
        'usage': {'context_percent': 42},
      });
      return {'status': 'streaming'};
  }
  return null;
}

/// Asks for less motion, which stills the effort bar's stripes: running, they never let a test settle.
void stillStripes(WidgetTester t) {
  t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Taps [effort]'s place on the effort bar.
Future<void> tapEffort(WidgetTester t, String effort) async {
  final bar = t.getRect(find.byKey(const ValueKey('effort')));
  await t.tapAt(Offset(bar.left + 17 + (bar.width - 34) * efforts.indexOf(effort) / (efforts.length - 1), bar.center.dy));
}

/// Fresh settings, no chat connection and no subagents before each test.
void resetApp() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await settings.load();
    dropGateway();
    subagents.value = const {};
    addTearDown(() => connectGateway = hermesGateway);
    // a phone tall enough for the whole menu (its pages, then the chats) to be in view
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(2400, 3000);
    addTearDown(view.resetPhysicalSize);
  });
}
