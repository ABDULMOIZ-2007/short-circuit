import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Pointer<Utf8> Function(Pointer<Utf8>)>(
  symbol: 'sc_request',
  assetId: 'package:short_circuit_core/short_circuit_core.dart',
)
external Pointer<Utf8> _request(Pointer<Utf8> input);
@Native<Void Function(Pointer<Utf8>)>(
  symbol: 'sc_free',
  assetId: 'package:short_circuit_core/short_circuit_core.dart',
)
external void _free(Pointer<Utf8> output);

/// Each call creates and destroys a C++ Circuit; no native handles escape.
Map<String, dynamic> executeNative(Map<String, dynamic> request) {
  final input = jsonEncode(request).toNativeUtf8();
  Pointer<Utf8>? output;
  try {
    output = _request(input);
    if (output.address == 0) {
      throw StateError('Native response allocation failed.');
    }
    final response = jsonDecode(output.toDartString()) as Map<String, dynamic>;
    if (response['ok'] != true) {
      throw StateError(
        response['error'] as String? ?? 'Native operation failed.',
      );
    }
    return response;
  } finally {
    malloc.free(input);
    if (output != null && output.address != 0) _free(output);
  }
}
