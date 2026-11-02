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

    // stopped mid-script, the next step gets a new shell in the same place
    final slow = sh.run('echo start; sleep 30', (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 500));
    sh.stop();
    final (code, out) = await slow;
    expect(code, isNot(0));
    expect(out, 'start\n\n[stopped by the user]');
    expect(await sh.run('pwd -P', (_) {}), (0, '${dir.resolveSymbolicLinksSync()}\n'));

    expect((await sh.run('sleep 5', (_) {}, timeout: const Duration(seconds: 1))).$2, contains('[timed out after 0 min]'));
  }, skip: !macCapable);
}
