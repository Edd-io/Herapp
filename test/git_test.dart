import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/git_page.dart';
import 'package:herapp/mac.dart';

void main() {
  test("a folder of this computer is reviewed with its own git, as the server's routes answer", () async {
    final dir = await Directory.systemTemp.createTemp('git');
    addTearDown(() => dir.delete(recursive: true));
    expect(await localGit('GET', '/api/git/status', query: {'path': dir.path}), isNull); // not a repository
    Future<void> git(List<String> args) => Process.run('git', ['-C', dir.path, ...args]);
    await git(['init', '-q', '-b', 'main']);
    await git(['config', 'user.email', 'me@test']);
    await git(['config', 'user.name', 'Me']);
    File('${dir.path}/a.txt').writeAsStringSync('one\n');
    await git(['add', '.']);
    await git(['commit', '-qm', 'first']);
    File('${dir.path}/a.txt').writeAsStringSync('two\n');
    File('${dir.path}/new.txt').writeAsStringSync('hi\n');

    expect(await localGit('GET', '/api/git/status', query: {'path': dir.path}), {'branch': 'main', 'ahead': 0, 'behind': 0});
    expect(((await localGit('GET', '/api/git/review/list', query: {'path': dir.path})) as Map)['files'], [
      {'path': 'a.txt', 'status': 'M', 'added': 1, 'removed': 1},
      {'path': 'new.txt', 'status': '?', 'added': 0, 'removed': 0},
    ]);
    final diff = (await localGit('GET', '/api/git/review/diff', query: {'path': dir.path, 'file': 'new.txt'})) as Map;
    expect(diff['diff'], contains('+hi'));

    await localGit('POST', '/api/git/review/commit', body: {'path': dir.path, 'message': 'second'});
    expect(((await localGit('GET', '/api/git/review/list', query: {'path': dir.path})) as Map)['files'], isEmpty);
    await expectLater(localGit('POST', '/api/git/review/push', body: {'path': dir.path}), throwsA(isA<HttpException>())); // no remote
  }, skip: !macCapable);
}
