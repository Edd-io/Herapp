import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/mac.dart';

void main() {
  test('a chat keeps one shell: its directory carries over, each step reports its exit code and output', () async {
    final dir = await Directory.systemTemp.createTemp('mac');
    addTearDown(() => dir.delete(recursive: true));
    final sh = MacShell();
    addTearDown(sh.stop);
    final seen = <String>[];
    expect(await sh.run('cd ${dir.path} && echo one && echo two >&2', seen.add), (0, 'one\ntwo\n'));
    expect(sh.cwd, dir.path);
    expect(await sh.run('pwd; false', (_) {}), (1, '${dir.path}\n'));
    expect(await sh.run('cat', (_) {}), (0, '')); // no stdin to wait on

    expect(sh.write('sub/a.txt', 'hi'), (0, 'wrote 2 bytes to ${dir.path}/sub/a.txt'));
    expect(await sh.run('cat sub/a.txt', (_) {}), (0, 'hi'));

    // what a program prints shows as it goes, even one that holds it back when not on a terminal
    final lines = <String>[];
    final slow = sh.run(r'''perl -e 'print "start\n"; sleep 30' ''', lines.add);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(lines.last, 'start\n');
    // stopped as Ctrl-C would, the shell goes on in the same place
    sh.stop();
    expect(await slow, (130, 'start\n\n[stopped by the user]'));
    expect(await sh.run('pwd -P', (_) {}), (0, '${dir.resolveSymbolicLinksSync()}\n'));

    expect((await sh.run('sleep 5', (_) {}, timeout: const Duration(seconds: 1))).$2, contains('[timed out after 0 min]'));
  }, skip: !macCapable);
}
