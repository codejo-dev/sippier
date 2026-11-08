import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Builds libsippier_core with native/scripts/build.sh for the target OS and
/// architecture, and bundles it with the app.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final repo = input.packageRoot.resolve('../../');
    final arch = code.targetArchitecture.name;
    final environment = <String, String>{};

    var shell = 'bash';
    final shellArgs = <String>[];
    var script = repo.resolve('native/scripts/build.sh').toFilePath();

    final String os;
    final String minVersion;
    switch (code.targetOS) {
      case OS.macOS:
        os = 'macos';
        // Xcode 27 can't target anything older than macOS 12
        final major = code.macOS.targetVersion;
        minVersion = '${major < 12 ? 12 : major}.0';
      case OS.android:
        os = 'android';
        minVersion = '${code.android.targetNdkApi}';
        // .../ndk/<version>/toolchains/llvm/prebuilt/<host>/bin/clang
        final clang = code.cCompiler?.compiler;
        if (clang != null) {
          environment['ANDROID_NDK_ROOT'] = clang
              .resolve('../../../../../')
              .toFilePath();
        }
      case OS.windows:
        os = 'windows';
        minVersion = '';
        // build.sh runs in MSYS2's clang environment for the target
        environment['MSYSTEM'] = switch (code.targetArchitecture) {
          Architecture.arm64 => 'CLANGARM64',
          Architecture.x64 => 'CLANG64',
          final other => throw UnsupportedError(
            'sippier_core: windows-${other.name} is not supported',
          ),
        };
        shell = _msys2Bash();
        shellArgs.add('-l'); // sets PATH for MSYSTEM
        script = script.replaceAll(r'\', '/');
      default:
        throw UnsupportedError(
          'sippier_core: ${code.targetOS} is not supported yet',
        );
    }

    final result = await Process.run(shell, [
      ...shellArgs,
      script,
      os,
      arch,
      minVersion,
    ], environment: environment);
    stdout.write(result.stdout);
    if (result.exitCode != 0) {
      stderr.write(result.stderr);
      throw ProcessException(
        script,
        [os, arch, minVersion],
        'native build failed',
        result.exitCode,
      );
    }

    final libName = code.targetOS.dylibFileName('sippier_core');
    final bundled = input.outputDirectory.resolve(libName);
    await File.fromUri(
      repo.resolve('build/$os-$arch/lib/$libName'),
    ).copy(bundled.toFilePath());

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/bindings.dart',
        linkMode: DynamicLoadingBundled(),
        file: bundled,
      ),
    );

    // Rebuild when our native sources change. After bumping a submodule,
    // touch native/scripts/build.sh.
    for (final dir in [
      'native/scripts',
      'native/sippier_core',
      'native/patches',
    ]) {
      await for (final entity in Directory.fromUri(
        repo.resolve(dir),
      ).list(recursive: true)) {
        if (entity is File) output.dependencies.add(entity.uri);
      }
    }
  });
}

/// MSYS2's bash. Hooks only see a few environment variables, so MSYS2 is
/// found through PATH (its root folder, or its usr\bin), else in its default
/// place, C:\msys64.
String _msys2Bash() {
  final env = Platform.environment;
  final roots = [
    for (final dir in (env['PATH'] ?? '').split(';'))
      if (dir.isNotEmpty) ...[dir, '$dir\\..\\..'],
    '${env['SYSTEMDRIVE'] ?? 'C:'}\\msys64',
  ];
  for (final root in roots) {
    final bash = File('$root\\usr\\bin\\bash.exe');
    if (File('$root\\msys2.exe').existsSync() && bash.existsSync()) {
      return bash.absolute.path;
    }
  }
  throw UnsupportedError(
    'sippier_core: MSYS2 not found. Install it (winget install MSYS2.MSYS2) '
    'and put its folder on PATH if it is not C:\\msys64.',
  );
}
