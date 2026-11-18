import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:short_circuit_core/short_circuit_core.dart';

Map<String, dynamic> example(String name) =>
    jsonDecode(File('examples/$name.sc.json').readAsStringSync())
        as Map<String, dynamic>;
void main() {
  test('Real C++ FFI returns the 8 V divider and conserves power', () {
    final result =
        executeNative({
              'op': 'simulate',
              'project': example('divider'),
            })['result']
            as Map<String, dynamic>;
    final r2 = (result['components'] as List).firstWhere(
      (c) => c['id'] == 'R2',
    );
    expect(r2['voltage'], closeTo(8, 1e-9));
    expect(r2['current'], closeTo(.004, 1e-12));
    expect(result['powerBalance'], closeTo(0, 1e-10));
  });
  test('Real C++ RC transient agrees with the charging equation', () {
    final result =
        executeNative({
              'op': 'transient',
              'project': example('rc'),
              'duration': .05,
              'steps': 1000,
            })['result']
            as Map<String, dynamic>;
    final samples = result['samples'] as List;
    double capacitor(dynamic sample) =>
        ((sample['components'] as List).firstWhere(
                  (c) => c['id'] == 'C1',
                )['voltage']
                as num)
            .toDouble();
    expect(capacitor(samples.first), 0);
    expect(capacitor(samples.last), closeTo(5 * (1 - math.exp(-5)), .0005));
  });
  test('Real C++ recovery preserves drafts outside the project shelf', () {
    final directory = Directory.systemTemp.createTempSync(
      'short-circuit-test-',
    );
    final project = example('divider');
    Map<String, dynamic> call(Map<String, dynamic> request) =>
        executeNative({...request, 'directory': directory.path});
    expect(call({'op': 'restore'})['project'], isNull);
    call({'op': 'checkpoint', 'project': project, 'dirty': true});
    expect(call({'op': 'restore'})['project'], project);
    expect(call({'op': 'restore'})['dirty'], isTrue);
    expect(call({'op': 'list'})['projects'], isEmpty);
    call({'op': 'save', 'project': project});
    expect(
      (call({'op': 'list'})['projects'] as List).single['title'],
      project['title'],
    );
  });
  test('All nine packaged starter circuits solve using real native models', () {
    for (final name in [
      'divider',
      'parallel',
      'rc',
      'rl',
      'led',
      'zener',
      'switch',
      'potentiometer',
      'npn',
    ]) {
      final response = executeNative({
        'op': 'simulate',
        'project': example(name),
      });
      expect(response['ok'], isTrue, reason: name);
      final result = response['result'] as Map<String, dynamic>;
      expect(result['powerBalance'], closeTo(0, 1e-8), reason: name);
      final rows = result['components'] as List;
      if (name == 'led') {
        expect(
          rows.firstWhere((c) => c['id'] == 'X1')['current'],
          closeTo(.001, 1e-9),
        );
      }
      if (name == 'npn') {
        expect(rows.firstWhere((c) => c['id'] == 'Q1')['state'], 'Active');
      }
      if (name == 'zener') {
        expect(rows.firstWhere((c) => c['id'] == 'X1')['state'], 'Breakdown');
      }
    }
  });
}
