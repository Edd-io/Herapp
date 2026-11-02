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
  static String get shell => Platform.isMacOS ? '/bin/zsh' : Platform.environment['SHELL'] ?? '/bin/sh';

  String cwd = home;
  Process? _p;
  // the line the shell prints after each script, with its exit code and directory
  final _mark = '__herapp_${Random.secure().nextInt(1 << 32).toRadixString(16)}__';
  final _buf = StringBuffer();
  void Function(String)? _onOut;
  Completer<int>? _done;
  String _why = ''; // why the script was stopped

  /// What [macNote] says of this computer.
  String note(String token) => macNote(
    token: token,
    host: Platform.localHostname,
    os: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    shell: shell,
    home: home,
    cwd: cwd,
  );

  String get _printMark => "printf '\\n%s %d %s\\n' $_mark \$? \"\$PWD\"";

  Future<Process> _start() async {
    final dir = Directory(cwd).existsSync() ? cwd : home;
    const env = {'TERM': 'dumb', 'PAGER': 'cat', 'GIT_PAGER': 'cat', 'MANPAGER': 'cat'};
    // a terminal of its own, or programs keep what they print until they end; a login shell, for the PATH the
    // user's profile sets, and not an interactive one (no prompt, no .zshrc asking things): `+i` for zsh, and
    // commands read as a script from /dev/stdin for any shell
    Process p;
    try {
      p = Platform.isMacOS
          ? await Process.start('script', ['-q', '/dev/null', shell, '-l', '+i'], workingDirectory: dir, environment: env)
          : await Process.start('script', ['-qfec', "'$shell' -l /dev/stdin", '/dev/null'], workingDirectory: dir, environment: env);
    } on ProcessException {
      // no script(1) (a minimal Linux): pipes, where some programs print only once done and Ctrl-C can't reach
      p = await Process.start(shell, ['-l'], workingDirectory: dir, environment: env);
    }
    p.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(_read);
    p.stderr.drain<void>();
    p.exitCode.then((code) {
      if (identical(_p, p)) _p = null;
      if (_done case final d? when !d.isCompleted) d.complete(code); // it ended (`exit`, killed) mid-script
    });
    // no echo of what is typed, no \r before each \n; Ctrl-C ends the command, not the shell
    final ready = _done = Completer<int>();
    p.stdin.writeln('stty -echo -onlcr 2>/dev/null; trap : INT; exec 2>&1; $_printMark');
    await ready.future;
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
      _onOut?.call(_clean(all.split(_mark).first));
    }
  }

  /// [out] as a log reads it: no colors, and a line redrawn in place (a progress bar) only as it ended.
  static String _clean(String out) => out
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .split('\n')
      .map((l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l)
      .map((l) => l.split('\r').last)
      .join('\n');

  /// Runs [script], passing what it has printed so far to [onOut]; its exit code and output. A script still
  /// running after [timeout] is stopped.
  Future<(int, String)> run(String script, void Function(String) onOut, {Duration timeout = const Duration(minutes: 10)}) async {
    final p = _p ??= await _start();
    _buf.clear();
    _why = '';
    _onOut = onOut;
    // sourced from a file, as a terminal cuts long lines; no stdin, which a command would read for the next ones
    final file = File('${Directory.systemTemp.path}/herapp-$_mark-${DateTime.now().microsecondsSinceEpoch}.sh')
      ..writeAsStringSync('$script\n');
    final done = _done = Completer<int>();
    p.stdin.writeln("{ . '${file.path}'; } < /dev/null; $_printMark");
    final timer = Timer(timeout, () => stop('timed out after ${timeout.inMinutes} min'));
    final code = await done.future;
    timer.cancel();
    _onOut = null;
    file.delete().ignore();
    final out = _clean(_buf.toString().split(_mark).first);
    return (code, _why.isEmpty ? out : '$out\n[$_why]');
  }

  /// Ends the running script as Ctrl-C would, the shell staying; one that holds on is killed with the shell
  /// (the next step then starts a new one, in the same directory). Idle, it closes the shell.
  void stop([String why = 'stopped by the user']) {
    final p = _p;
    if (p == null) return;
    final running = _done;
    if (running == null || running.isCompleted) {
      _p = null;
      p.kill();
      return;
    }
    _why = why;
    p.stdin.add(const [3]);
    Timer(const Duration(seconds: 3), () {
      if (running.isCompleted || !identical(_p, p)) return;
      _p = null;
      // the shell's own children first, or they would outlive it
      Process.run('pkill', ['-TERM', '-P', '${p.pid}']).whenComplete(p.kill).ignore();
    });
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
