import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:short_circuit/current_flow.dart';
import 'package:short_circuit_core/short_circuit_core.dart';

Map<String, dynamic> project(String name) =>
    jsonDecode(File('examples/$name.sc.json').readAsStringSync())
        as Map<String, dynamic>;
Map<String, dynamic> solve(Map<String, dynamic> p) =>
    executeNative({'op': 'simulate', 'project': p})['result']
        as Map<String, dynamic>;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Series circuit becomes one continuous closed particle route', () {
    final p = project('divider'), g = CurrentFlowGeometry(p, solve(p), .8);
    expect(g.routes.length, 1);
    expect(g.routes.single.closed, isTrue);
    expect(g.routes.single.current, closeTo(.004, 1e-10));
    expect(g.routes.single.metric.length, greaterThan(1000));
  });
  test('Current splits retain distinct continuous branch streams', () {
    final p = project('parallel'), g = CurrentFlowGeometry(p, solve(p), .8);
    expect(g.routes.length, 3);
    expect(g.routes.every((r) => !r.closed), isTrue);
    final currents = g.routes.map((r) => r.current).toList()..sort();
    expect(currents[0], closeTo(.009, 1e-10));
    expect(currents[1], closeTo(.009, 1e-10));
    expect(currents[2], closeTo(.018, 1e-10));
  });
  test('Open switch leakage produces no particle geometry', () {
    final p = project('switch');
    expect(CurrentFlowGeometry(p, solve(p), 1).routes, isEmpty);
  });
  test(
    'Reversed supply preserves a closed stream with reversed native currents',
    () {
      final p = project('divider');
      (p['components'] as List).first['value'] = -12;
      final result = solve(p), g = CurrentFlowGeometry(p, result, .8);
      expect(
        (result['wires'] as List).every((w) => (w['current'] as num) < 0),
        isTrue,
      );
      expect(g.routes.length, 1);
      expect(g.routes.single.closed, isTrue);
      expect(g.routes.single.current, closeTo(.004, 1e-10));
    },
  );
}
