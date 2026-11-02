import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/screen_page.dart';

void main() {
  test('the screen client shakes hands, paints raw and copied rectangles, and sends the mouse and keys', () async {
    final server = StreamController<List<int>>();
    final sent = <List<int>>[];
    final rfb = Rfb(server.stream, sent.add);
    final frames = <String>[];
    rfb.onFrame = () => frames.add('${rfb.pixels}');
    final done = rfb.run();
    List<int> u16(int v) => [v >> 8, v & 255];
    List<int> u32(int v) => [...u16(v >> 16), ...u16(v & 0xffff)];
    // version, one security type (none), its result, then a 2×1 screen named "s"
    server.add([...ascii.encode('RFB 003.008\n'), 1, 1, ...u32(0)]);
    server.add([...u16(2), ...u16(1), ...List.filled(16, 0), ...u32(1), ...ascii.encode('s')]);
    // a raw rectangle split across two chunks (its padding byte comes as 0), then a copy of the left pixel to the right
    server.add([0, 0, ...u16(1), ...u16(0), ...u16(0), ...u16(2), ...u16(1), ...u32(0), 1, 2, 3, 0, 4]);
    server.add([5, 6, 0]);
    server.add([0, 0, ...u16(1), ...u16(1), ...u16(0), ...u16(1), ...u16(1), ...u32(1), ...u16(0), ...u16(0)]);
    await pumpEventQueue();
    expect(frames, ['[1, 2, 3, 255, 4, 5, 6, 255]', '[1, 2, 3, 255, 1, 2, 3, 255]']);
    expect(ascii.decode(sent[0]), 'RFB 003.008\n');
    expect(sent[1], [1]); // security: none
    expect(sent[2], [1]); // shared
    expect(sent.skip(3).first.first, 0); // pixel format, then encodings and the first full request
    expect(sent.last, [3, 1, 0, 0, 0, 0, 0, 2, 0, 1]); // asks for what changes next

    rfb
      ..pointer(5, 0, 1)
      ..type('é');
    expect(sent.sublist(sent.length - 3), [
      [5, 1, 0, 1, 0, 0], // x clamped to the screen
      [4, 1, 0, 0, 0, 0, 0, 0xe9],
      [4, 0, 0, 0, 0, 0, 0, 0xe9],
    ]);
    expect(keysymOf('€'.runes.first), 0x010020ac);

    await server.close();
    await expectLater(done, throwsA(anything));
  });
}
