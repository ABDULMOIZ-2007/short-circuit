import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    // Optional precompiled host library for Windows test environments without MSVC.
    // Android releases always compile the bundled C++ source through the NDK.
    final hostLibrary = input.packageRoot.resolve(
      '../../build/host/short_circuit_core.dll',
    );
    final testLibrary = File.fromUri(hostLibrary).existsSync()
        ? hostLibrary.toFilePath()
        : null;
    if (input.config.code.targetOS == OS.windows &&
        input.config.code.targetArchitecture == Architecture.x64 &&
        testLibrary != null) {
      final file = Uri.file(testLibrary);
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'short_circuit_core.dart',
          linkMode: DynamicLoadingBundled(),
          file: file,
        ),
      );
      output.dependencies.add(file);
      output.dependencies.add(input.packageRoot.resolve('src/engine.hpp'));
      output.dependencies.add(
        input.packageRoot.resolve('src/short_circuit.cpp'),
      );
      return;
    }
    final builder = CBuilder.library(
      name: 'short_circuit_core',
      assetName: 'short_circuit_core.dart',
      sources: ['src/short_circuit.cpp'],
      includes: ['src'],
      language: Language.cpp,
      std: 'c++17',
    );
    output.dependencies.add(input.packageRoot.resolve('src/engine.hpp'));
    output.dependencies.add(input.packageRoot.resolve('src/short_circuit.h'));
    await builder.run(input: input, output: output);
  });
}
