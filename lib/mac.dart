import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'hermes.dart';

/// Whether this computer can run what a reply asks of it (a desktop with a POSIX shell; the Mac app is out of the sandbox).
bool get macCapable => Platform.isMacOS || Platform.isLinux;

/// A shell kept open for one chat, so a `cd` or a variable carries over from one step to the next.
class MacShell {
  static String get home => Platform.environment['HOME'] ?? '/';
  static String get shell => Platform.environment['SHELL'] ?? '/bin/zsh';

  String cwd = home;
  Process? _p;
  // the line the shell prints after each script, with its exit code and directory
  final _mark = '__herapp_${Random.secure().nextInt(1 << 32).toRadixString(16)}__';
  final _buf = StringBuffer();
  void Function(String)? _onOut;
  Completer<int>? _done;
  String _why = ''; // why the shell was stopped mid-script

  /// What [macNote] says of this computer.
  String note(String token) => macNote(
    token: token,
    host: Platform.localHostname,
    os: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    shell: shell,
    home: home,
    cwd: cwd,
  );

  Future<Process> _start() async {
    // a login shell, for the PATH the user's profile sets
    final p = await Process.start(shell, ['-l'], workingDirectory: Directory(cwd).existsSync() ? cwd : home);
    p.stdin.writeln('exec 2>&1');
    p.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(_read);
    p.stderr.drain<void>();
    p.exitCode.then((code) {
      if (identical(_p, p)) _p = null;
      if (_done case final d? when !d.isCompleted) d.complete(code); // it ended (`exit`, killed) mid-script
    });
    return p;
  }

  void _read(String chunk) {
    _buf.write(chunk);
    final all = _buf.toString();
    if (RegExp('\\n$_mark (-?\\d+) (.*)\\n').firstMatch(all) case final m?) {
      _buf
        ..clear()
        ..write(all.substring(0, m.start));
      cwd = m[2]!;
      _done?.complete(int.parse(m[1]!));
    } else {
      _onOut?.call(all.split(_mark).first);
    }
  }

  /// Runs [script], passing what it has printed so far to [onOut]; its exit code and output. A script still
  /// running after [timeout] is stopped.
  Future<(int, String)> run(String script, void Function(String) onOut, {Duration timeout = const Duration(minutes: 10)}) async {
    final p = _p ??= await _start();
    _buf.clear();
    _why = '';
    _onOut = onOut;
    final done = _done = Completer<int>();
    // no stdin for the script: a command reading it would eat what comes after
    p.stdin.write("{\n$script\n} < /dev/null\nprintf '\\n%s %d %s\\n' $_mark \$? \"\$PWD\"\n");
    final timer = Timer(timeout, () => stop('timed out after ${timeout.inMinutes} min'));
    final code = await done.future;
    timer.cancel();
    _onOut = null;
    final out = _buf.toString().split(_mark).first;
    return (code, _why.isEmpty ? out : '$out\n[$_why]');
  }

  /// Ends the running script, and the shell with it (the next step starts a new one, in the same directory).
  void stop([String why = 'stopped by the user']) {
    final p = _p;
    if (p == null) return;
    _p = null;
    if (_done?.isCompleted ?? true) {
      p.kill(); // idle: no command of its own to end
      return;
    }
    _why = why;
    Process.run('pkill', ['-TERM', '-P', '${p.pid}']).whenComplete(p.kill).ignore();
  }

  /// Writes [content] to [path]; an exit code and what to tell, as [run] does.
  (int, String) write(String path, String content) {
    final abs = macPath(path, home: home, cwd: cwd);
    try {
      File(abs)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
      return (0, 'wrote ${utf8.encode(content).length} bytes to $abs');
    } on FileSystemException catch (e) {
      return (1, '${e.message}: $abs${e.osError == null ? '' : ' (${e.osError!.message})'}');
    }
  }
}
