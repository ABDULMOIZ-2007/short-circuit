import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'project_view.dart';

const currentColor = Color(0xfff4cd79);

class FlowRoute {
  FlowRoute(this.metric, this.current, this.closed);
  final ui.PathMetric metric;
  final double current;
  final bool closed;
}

class _Edge {
  _Edge(this.from, this.to, this.points, this.current);
  final String from, to;
  final List<Offset> points;
  final double current;
}

/// Render-only geometry. Electrical currents and directions always come from C++.
class CurrentFlowGeometry {
  CurrentFlowGeometry(
    Map<String, dynamic> project,
    Map<String, dynamic> result,
    double scale,
  ) {
    final edges = <_Edge>[];
    void add(String from, String to, List<Offset> points, Object? value) {
      if (!CurrentFlowPainter.carriesCurrent(value)) return;
      final i = (value as num).toDouble();
      edges.add(
        i > 0
            ? _Edge(from, to, points, i)
            : _Edge(to, from, points.reversed.toList(), -i),
      );
    }

    for (final row in (result['wires'] as List? ?? [])) {
      if (row['determinate'] != true) continue;
      final from = row['from'] as String, to = row['to'] as String;
      final a = terminalPosition(project, from),
          b = terminalPosition(project, to);
      if (a != null && b != null) {
        add(from, to, [a, wireCorner(project, from, a, b), b], row['current']);
      }
    }
    final readings = {
      for (final row in (result['components'] as List? ?? [])) row['id']: row,
    };
    for (final part in componentsOf(project)) {
      final id = part['id'] as String, row = readings[id];
      if (row == null) continue;
      final count = pinCount(part['type'] as String);
      if (count == 2) {
        var local = <Offset>[const Offset(-48, 0), const Offset(48, 0)];
        if (part['type'] == 'resistor') {
          local = const [
            Offset(-48, 0),
            Offset(-28, 0),
            Offset(-22, -11),
            Offset(-14, 11),
            Offset(-6, -11),
            Offset(2, 11),
            Offset(10, -11),
            Offset(18, 11),
            Offset(25, 0),
            Offset(48, 0),
          ];
        }
        if (part['type'] == 'inductor') {
          local = [const Offset(-48, 0), const Offset(-28, 0)];
          for (int coil = 0; coil < 4; coil++) {
            for (int step = 1; step <= 10; step++) {
              final t = step / 10.0;
              local.add(
                Offset(
                  -28 + coil * 14 + 14 * (3 * t * t - 2 * t * t * t),
                  -63 * t * (1 - t),
                ),
              );
            }
          }
          local.add(const Offset(48, 0));
        }
        final angle = (part['rotation'] as num) * math.pi / 180,
            center = Offset(
              (part['x'] as num).toDouble(),
              (part['y'] as num).toDouble(),
            );
        final points = local
            .map(
              (p) =>
                  center +
                  Offset(
                    p.dx * math.cos(angle) - p.dy * math.sin(angle),
                    p.dx * math.sin(angle) + p.dy * math.cos(angle),
                  ),
            )
            .toList();
        add('$id:0', '$id:1', points, row['current']);
      }
      if (count == 3 && row['terminalCurrents'] is List) {
        final type = part['type'] as String;
        final angle = (part['rotation'] as num) * math.pi / 180,
            center = Offset(
              (part['x'] as num).toDouble(),
              (part['y'] as num).toDouble(),
            );
        Offset world(Offset p) =>
            center +
            Offset(
              p.dx * math.cos(angle) - p.dy * math.sin(angle),
              p.dx * math.sin(angle) + p.dy * math.cos(angle),
            );
        final paths = type == 'potentiometer'
            ? <List<Offset>>[
                const [
                  Offset(-48, 0),
                  Offset(-28, 0),
                  Offset(-22, -11),
                  Offset(-14, 11),
                  Offset(-6, -11),
                  Offset(0, 6),
                ],
                const [
                  Offset(48, 0),
                  Offset(25, 0),
                  Offset(18, 11),
                  Offset(10, -11),
                  Offset(2, 11),
                  Offset(0, 6),
                ],
                const [Offset(0, 48), Offset(0, 6)],
              ]
            : <List<Offset>>[
                const [
                  Offset(24, -48),
                  Offset(24, -34),
                  Offset(-10, -15),
                  Offset(-10, 0),
                ],
                const [
                  Offset(24, 48),
                  Offset(24, 34),
                  Offset(-10, 15),
                  Offset(-10, 0),
                ],
                const [Offset(-48, 0), Offset(-10, 0)],
              ];
        for (int pin = 0; pin < 3; pin++) {
          add(
            '$id:$pin',
            '$id@core',
            paths[pin].map(world).toList(),
            row['terminalCurrents'][pin],
          );
        }
      }
    }
    final incoming = <String, List<int>>{}, outgoing = <String, List<int>>{};
    for (int i = 0; i < edges.length; i++) {
      incoming.putIfAbsent(edges[i].to, () => []).add(i);
      outgoing.putIfAbsent(edges[i].from, () => []).add(i);
    }
    bool equal(double a, double b) =>
        (a - b).abs() <= math.max(1e-12, math.max(a, b) * 1e-6);
    bool joins(int previous, int next) =>
        edges[previous].to == edges[next].from &&
        incoming[edges[previous].to]?.length == 1 &&
        outgoing[edges[previous].to]?.length == 1 &&
        equal(edges[previous].current, edges[next].current);
    final used = <int>{};
    void trace(int first) {
      if (used.contains(first)) return;
      final points = <Offset>[];
      int index = first;
      while (!used.contains(index)) {
        final e = edges[index];
        used.add(index);
        for (final p in e.points) {
          if (points.isEmpty || (p - points.last).distance > .001) {
            points.add(p);
          }
        }
        final next = outgoing[e.to];
        if (next?.length != 1 || !joins(index, next!.single)) break;
        index = next.single;
      }
      if (points.length < 2) return;
      final closed = (points.first - points.last).distance < .01;
      final path = schematicPolyline(points, 5 / scale.clamp(.08, 5.0));
      for (final metric in path.computeMetrics()) {
        if (metric.length > 1) {
          routes.add(FlowRoute(metric, edges[first].current, closed));
        }
      }
    }

    // Start at junctions first, then collect closed series loops.
    for (int i = 0; i < edges.length; i++) {
      final previous = incoming[edges[i].from];
      if (previous?.length != 1 || !joins(previous!.single, i)) trace(i);
    }
    for (int i = 0; i < edges.length; i++) {
      trace(i);
    }
  }
  final routes = <FlowRoute>[];
}

/// Connected particle streams preserve continuity through series components.
/// Speed is a visual magnitude cue, not electron drift speed.
class CurrentFlowPainter extends CustomPainter {
  CurrentFlowPainter(
    this.project,
    this.result, {
    required this.clock,
    this.viewScale = 1,
    this.lightCanvas = false,
  }) : geometry = CurrentFlowGeometry(project, result, viewScale),
       super(repaint: clock);
  final Map<String, dynamic> project, result;
  final Animation<double> clock;
  final double viewScale;
  final bool lightCanvas;
  final CurrentFlowGeometry geometry;
  static bool carriesCurrent(Object? value) =>
      value is num && value.isFinite && value.abs() >= 1e-9;
  @override
  void paint(Canvas canvas, Size size) {
    final zoom = viewScale.clamp(.08, 5.0),
        clip = canvas.getLocalClipBounds().inflate(20 / zoom);
    final color = lightCanvas ? const Color(0xffb16c13) : currentColor;
    final tail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8 / zoom;
    final halo = Paint()
      ..color = color.withValues(alpha: lightCanvas ? .14 : .16);
    final core = Paint()
      ..color = lightCanvas ? const Color(0xffd79428) : const Color(0xfffff1c8);
    for (final route in geometry.routes) {
      final metric = route.metric;
      final count = (metric.length * zoom / 37).round().clamp(1, 700);
      final spacing = metric.length / count;
      final speed = (22 + 23 * math.log(1 + route.current * 1000)).clamp(
        22.0,
        105.0,
      );
      final cycles = math.max(1, (speed * 10 / (spacing * zoom)).round());
      final advance = ((clock.value * cycles) % 1) * spacing;
      for (int n = 0; n < count; n++) {
        final distance = (n * spacing + advance) % metric.length;
        final tangent = metric.getTangentForOffset(distance);
        if (tangent == null || !clip.contains(tangent.position)) continue;
        final length = math.min(10 / zoom, metric.length * .25);
        for (int segment = 4; segment >= 0; segment--) {
          final end = distance - length * segment / 5, start = end - length / 5;
          tail.color = color.withValues(alpha: (5 - segment) * .12);
          if (start >= 0) {
            canvas.drawPath(metric.extractPath(start, end), tail);
          } else if (route.closed) {
            if (end > 0) canvas.drawPath(metric.extractPath(0, end), tail);
            canvas.drawPath(
              metric.extractPath(
                metric.length + start,
                math.min(metric.length, metric.length + end),
              ),
              tail,
            );
          }
        }
        canvas.drawCircle(tangent.position, 3.7 / zoom, halo);
        canvas.drawCircle(tangent.position, 1.65 / zoom, core);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CurrentFlowPainter old) =>
      old.project != project ||
      old.result != result ||
      old.viewScale != viewScale ||
      old.lightCanvas != lightCanvas ||
      old.clock != clock;
}
