import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Builds the WireGuard tunnel (native/wg, Go) as a dynamic library for the target.
void main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildCodeAssets) return;
  final code = input.config.code;
  final src = input.packageRoot.resolve('native/wg/');
  final lib = input.outputDirectory.resolve('libwg.dylib');
  final arch = switch (code.targetArchitecture) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'amd64',
    final a => throw UnsupportedError('WireGuard : architecture $a non prise en charge'),
  };
  final go = ['build', '-trimpath'];

  switch (code.targetOS) {
    case OS.iOS:
      final sdk = code.iOS.targetSdk == IOSSdk.iPhoneSimulator ? 'iphonesimulator' : 'iphoneos';
      final target =
          '${arch == 'amd64' ? 'x86_64' : 'arm64'}-apple-ios${code.iOS.targetVersion}${sdk == 'iphonesimulator' ? '-simulator' : ''}';
      final sysroot = await _run('xcrun', ['--sdk', sdk, '--show-sdk-path']);
      final clang = await _run('xcrun', ['--sdk', sdk, '-f', 'clang']);
      final archive = input.outputDirectory.resolve('libwg.a').toFilePath();
      await _run(
        'go',
        [...go, '-buildmode=c-archive', '-o', archive, '.'],
        dir: src,
        env: {'CGO_ENABLED': '1', 'GOOS': 'ios', 'GOARCH': arch, 'CC': '$clang -isysroot $sysroot -target $target'},
      );
      // Go can't build c-shared for iOS: link the archive into a dylib instead.
      await _run(clang, [
        ...['-isysroot', sysroot, '-target', target, '-dynamiclib', '-o', lib.toFilePath()],
        ...['-Wl,-all_load', archive, '-framework', 'CoreFoundation', '-framework', 'Security', '-lresolv'],
        ...['-install_name', '@rpath/libwg.dylib', '-headerpad_max_install_names'],
      ]);
    case OS.macOS:
      final min = '-mmacosx-version-min=${code.macOS.targetVersion}';
      // Xcode's build environment hides the SDK from a bare clang: name it, as for iOS
      final sysroot = await _run('xcrun', ['--sdk', 'macosx', '--show-sdk-path']);
      final clang = await _run('xcrun', ['--sdk', 'macosx', '-f', 'clang']);
      await _run(
        'go',
        [...go, '-buildmode=c-shared', '-o', lib.toFilePath(), '.'],
        dir: src,
        env: {
          'CGO_ENABLED': '1',
          'GOOS': 'darwin',
          'GOARCH': arch,
          'CC': '$clang -isysroot $sysroot -arch ${arch == 'amd64' ? 'x86_64' : 'arm64'}',
          'CGO_CFLAGS': min,
          'CGO_LDFLAGS': '$min -Wl,-install_name,@rpath/libwg.dylib -Wl,-headerpad_max_install_names',
        },
      );
    default:
      // ponytail: Apple only; Android/Linux/Windows = go c-shared with the compiler from code.cCompiler
      return;
  }
  output.assets.code.add(CodeAsset(package: input.packageName, name: 'wireguard.dart', linkMode: DynamicLoadingBundled(), file: lib));
  output.dependencies.addAll([
    for (final f in ['wg.go', 'go.mod', 'go.sum']) src.resolve(f),
  ]);
});

Future<String> _run(String exe, List<String> args, {Uri? dir, Map<String, String>? env}) async {
  final r = await Process.run(exe, args, workingDirectory: dir?.toFilePath(), environment: env);
  if (r.exitCode != 0) throw Exception('$exe ${args.join(' ')}\n${r.stdout}${r.stderr}');
  return (r.stdout as String).trim();
}
