import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

const accent = Color(0xffd4f57a),
    muted = Color(0xff8b9c9f),
    panel = Color(0xff151e22),
    edge = Color(0xff2a373b);
const worldWidth = 4800.0, worldHeight = 3200.0;
const componentNames = <String, String>{
  'resistor': 'Resistor',
  'capacitor': 'Capacitor',
  'inductor': 'Inductor',
  'potentiometer': 'Potentiometer',
  'switch': 'Switch',
  'voltage': 'Voltage source',
  'current': 'Current source',
  'ground': 'Ground',
  'diode': 'Diode',
  'led': 'LED',
  'zener': 'Zener diode',
  'npn': 'NPN transistor',
  'pnp': 'PNP transistor',
};
const componentUnits = <String, String>{
  'resistor': 'Ω',
  'capacitor': 'F',
  'inductor': 'H',
  'potentiometer': 'Ω',
  'switch': '',
  'voltage': 'V',
  'current': 'A',
  'ground': '',
  'diode': 'V',
  'led': 'V',
  'zener': 'V',
  'npn': '',
  'pnp': '',
};
const componentPrefixes = <String, String>{
  'resistor': 'R',
  'capacitor': 'C',
  'inductor': 'L',
  'potentiometer': 'RV',
  'switch': 'S',
  'voltage': 'V',
  'current': 'I',
  'ground': 'G',
  'diode': 'D',
  'led': 'LED',
  'zener': 'ZD',
  'npn': 'Q',
  'pnp': 'Q',
};
const componentDefaults = <String, double>{
  'resistor': 1000,
  'capacitor': .00001,
  'inductor': .01,
  'potentiometer': 10000,
  'switch': 0,
  'voltage': 12,
  'current': .001,
  'ground': 0,
  'diode': .7,
  'led': 2,
  'zener': 5.1,
  'npn': 100,
  'pnp': 100,
};
const componentCategories = <String, String>{
  'resistor': 'Passives',
  'capacitor': 'Passives',
  'inductor': 'Passives',
  'potentiometer': 'Passives',
  'switch': 'Passives',
  'voltage': 'Sources',
  'current': 'Sources',
  'ground': 'Sources',
  'diode': 'Semiconductors',
  'led': 'Semiconductors',
  'zener': 'Semiconductors',
  'npn': 'Semiconductors',
  'pnp': 'Semiconductors',
};
const componentDescriptions = <String, String>{
  'resistor': 'Set resistance and control current.',
  'capacitor': 'Store charge; simulate RC and RLC responses.',
  'inductor': 'Store magnetic energy; simulate RL and RLC responses.',
  'potentiometer': 'Three terminals with an adjustable wiper.',
  'switch': 'Open or close a branch. Double-tap to toggle.',
  'voltage': 'An independent DC voltage supply.',
  'current': 'An independent DC current supply.',
  'ground': 'The common 0 V reference.',
  'diode': 'Nonlinear silicon junction with anode and cathode.',
  'led': 'A light-emitting junction with a visible powered state.',
  'zener': 'Forward conduction and reverse-voltage regulation.',
  'npn': 'Three-terminal Ebers–Moll transistor model.',
  'pnp': 'Complementary three-terminal transistor model.',
};
int pinCount(String type) => type == 'ground'
    ? 1
    : ['npn', 'pnp', 'potentiometer'].contains(type)
    ? 3
    : 2;
List<String> pinNames(String type) => switch (type) {
  'npn' || 'pnp' => const ['C', 'E', 'B'],
  'potentiometer' => const ['A', 'B', 'W'],
  'diode' || 'led' || 'zener' => const ['A', 'K'],
  'ground' => const ['0 V'],
  _ => const ['+', '−'],
};
String componentValue(Map<String, dynamic> c) {
  final type = c['type'] as String;
  if (type == 'ground') return '0 V';
  if (type == 'switch') return (c['value'] as num) > .5 ? 'Closed' : 'Open';
  if (type == 'npn' || type == 'pnp') {
    return 'β ${engineering(c['value'] as num).trim()}';
  }
  return engineering(c['value'] as num, componentUnits[type] ?? '');
}

Map<String, dynamic> copyProject(Map<String, dynamic> p) =>
    jsonDecode(jsonEncode(p)) as Map<String, dynamic>;
List<Map<String, dynamic>> componentsOf(Map<String, dynamic> p) =>
    (p['components'] as List).cast<Map<String, dynamic>>();
List<Map<String, dynamic>> wiresOf(Map<String, dynamic> p) =>
    (p['wires'] as List).cast<Map<String, dynamic>>();
String engineering(num value, [String unit = '']) {
  if (!value.isFinite) return '—';
  if (value.abs() < 1e-15 || value == 0) return '0 $unit';
  final scales = <double, String>{
    1e12: 'T',
    1e9: 'G',
    1e6: 'M',
    1e3: 'k',
    1: '',
    1e-3: 'm',
    1e-6: 'µ',
    1e-9: 'n',
    1e-12: 'p',
  };
  for (final e in scales.entries) {
    if (value.abs() >= e.key || e.key == 1e-12) {
      return '${num.parse((value / e.key).toStringAsPrecision(4))} ${e.value}$unit';
    }
  }
  return '$value $unit';
}

double parseEngineering(String text) {
  final m = RegExp(
    r'^([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)\s*([TGMkmunpµμ]?)(?:Ω|ohm|V|A|F|H)?$',
  ).firstMatch(text.trim());
  if (m == null) {
    throw const FormatException('Use a value such as 4.7k, 10µ, or 0.001.');
  }
  const f = <String, double>{
    '': 1,
    'T': 1e12,
    'G': 1e9,
    'M': 1e6,
    'k': 1e3,
    'm': 1e-3,
    'u': 1e-6,
    'µ': 1e-6,
    'μ': 1e-6,
    'n': 1e-9,
    'p': 1e-12,
  };
  final v = double.parse(m[1]!) * f[m[2]!]!;
  if (!v.isFinite) throw const FormatException('Enter a finite number.');
  return v;
}

Offset localPin(String type, int terminal) {
  if (type == 'ground') return Offset.zero;
  if (type == 'npn' || type == 'pnp') {
    return const [Offset(24, -48), Offset(24, 48), Offset(-48, 0)][terminal];
  }
  if (type == 'potentiometer' && terminal == 2) return const Offset(0, 48);
  return Offset(terminal == 0 ? -48 : 48, 0);
}

Offset pinPosition(Map<String, dynamic> c, int terminal) {
  final local = localPin(c['type'] as String, terminal),
      angle = (c['rotation'] as num? ?? 0) * math.pi / 180;
  return Offset((c['x'] as num).toDouble(), (c['y'] as num).toDouble()) +
      Offset(
        local.dx * math.cos(angle) - local.dy * math.sin(angle),
        local.dx * math.sin(angle) + local.dy * math.cos(angle),
      );
}

Offset? terminalPosition(Map<String, dynamic> p, String terminal) {
  final t = terminal.split(':');
  if (t.length != 2) return null;
  final index = int.tryParse(t[1]);
  if (index == null) return null;
  for (final c in componentsOf(p)) {
    if (c['id'] == t[0] &&
        index >= 0 &&
        index < pinCount(c['type'] as String)) {
      return pinPosition(c, index);
    }
  }
  return null;
}

Offset wireCorner(
  Map<String, dynamic> project,
  String from,
  Offset a,
  Offset b,
) {
  final source = componentsOf(
    project,
  ).firstWhere((c) => c['id'] == from.split(':')[0]);
  final direction =
      a -
      Offset((source['x'] as num).toDouble(), (source['y'] as num).toDouble());
  return direction.dy.abs() > direction.dx.abs()
      ? Offset(a.dx, b.dy)
      : Offset(b.dx, a.dy);
}

Path schematicPolyline(List<Offset> points, double radius) {
  final p = Path()..moveTo(points.first.dx, points.first.dy);
  for (int i = 1; i < points.length - 1; i++) {
    final a = points[i - 1], b = points[i], c = points[i + 1];
    final before = b - a, after = c - b;
    if (before.distance < .01 || after.distance < .01) continue;
    final cosine =
        (before.dx * after.dx + before.dy * after.dy) /
        (before.distance * after.distance);
    final bend = cosine.abs() < .05 ? radius : radius * .22;
    final r = math.min(bend, math.min(before.distance, after.distance) / 2);
    final start = b - before / before.distance * r,
        end = b + after / after.distance * r;
    p.lineTo(start.dx, start.dy);
    p.quadraticBezierTo(b.dx, b.dy, end.dx, end.dy);
  }
  p.lineTo(points.last.dx, points.last.dy);
  return p;
}

void drawCircuitSymbol(Canvas canvas, String type, double value, Paint pen) {
  void line(double x, double y, double xx, double yy) =>
      canvas.drawLine(Offset(x, y), Offset(xx, yy), pen);
  void arrow(Offset a, Offset b) {
    canvas.drawLine(a, b, pen);
    final d = (a - b) / (a - b).distance,
        side = Offset(-(a - b).dy, (a - b).dx) / (a - b).distance;
    canvas.drawLine(b, b + d * 9 + side * 4, pen);
    canvas.drawLine(b, b + d * 9 - side * 4, pen);
  }

  switch (type) {
    case 'resistor':
    case 'potentiometer':
      canvas.drawPath(
        Path()
          ..moveTo(-48, 0)
          ..lineTo(-28, 0)
          ..lineTo(-22, -11)
          ..lineTo(-14, 11)
          ..lineTo(-6, -11)
          ..lineTo(2, 11)
          ..lineTo(10, -11)
          ..lineTo(18, 11)
          ..lineTo(25, 0)
          ..lineTo(48, 0),
        pen,
      );
      if (type == 'potentiometer') {
        arrow(const Offset(0, 48), const Offset(0, 9));
      }
    case 'capacitor':
      line(-48, 0, -7, 0);
      line(7, 0, 48, 0);
      line(-7, -24, -7, 24);
      line(7, -24, 7, 24);
    case 'inductor':
      line(-48, 0, -28, 0);
      final path = Path()..moveTo(-28, 0);
      for (int i = 0; i < 4; i++) {
        final x = -28 + i * 14.0;
        path.cubicTo(x, -21, x + 14, -21, x + 14, 0);
      }
      path.lineTo(48, 0);
      canvas.drawPath(path, pen);
    case 'voltage':
    case 'current':
      line(-48, 0, -24, 0);
      line(24, 0, 48, 0);
      canvas.drawCircle(Offset.zero, 24, pen);
      if (type == 'voltage') {
        line(-12, -8, -2, -8);
        line(-7, -13, -7, -3);
        line(1, 9, 11, 9);
      } else {
        arrow(const Offset(-12, 0), const Offset(12, 0));
      }
    case 'switch':
      line(-48, 0, -20, 0);
      line(20, 0, 48, 0);
      canvas.drawCircle(const Offset(-20, 0), 3, pen);
      canvas.drawCircle(const Offset(20, 0), 3, pen);
      line(-17, 0, 17, value > .5 ? 0 : -20);
    case 'diode':
    case 'led':
    case 'zener':
      line(-48, 0, -17, 0);
      line(17, 0, 48, 0);
      canvas.drawPath(
        Path()
          ..moveTo(-17, -21)
          ..lineTo(-17, 21)
          ..lineTo(17, 0)
          ..close(),
        pen,
      );
      line(17, -21, 17, 21);
      if (type == 'zener') {
        line(17, -21, 25, -25);
        line(17, 21, 9, 25);
      }
      if (type == 'led') {
        arrow(const Offset(-4, -26), const Offset(9, -39));
        arrow(const Offset(13, -24), const Offset(26, -37));
      }
    case 'npn':
    case 'pnp':
      line(-48, 0, -10, 0);
      line(-10, -23, -10, 23);
      line(-10, -15, 24, -34);
      line(24, -34, 24, -48);
      line(-10, 15, 24, 34);
      line(24, 34, 24, 48);
      if (type == 'npn') {
        arrow(const Offset(1, 21), const Offset(23, 33));
      } else {
        arrow(const Offset(23, 33), const Offset(1, 21));
      }
    case 'ground':
      line(0, 0, 0, 17);
      line(-22, 17, 22, 17);
      line(-14, 26, 14, 26);
      line(-6, 35, 6, 35);
  }
}

class SymbolPreview extends StatelessWidget {
  const SymbolPreview(
    this.type, {
    super.key,
    this.size = 44,
    this.color = accent,
    this.value,
  });
  final String type;
  final double size;
  final Color color;
  final double? value;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _SymbolPreviewPainter(
      type,
      color,
      value ?? componentDefaults[type] ?? 0,
    ),
  );
}

class _SymbolPreviewPainter extends CustomPainter {
  _SymbolPreviewPainter(this.type, this.color, this.value);
  final String type;
  final Color color;
  final double value;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.width / 122, size.height / 122);
    drawCircuitSymbol(
      canvas,
      type,
      value,
      Paint()
        ..color = color
        ..strokeWidth = 3.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SymbolPreviewPainter old) =>
      old.type != type || old.color != color || old.value != value;
}

class CircuitPainter extends CustomPainter {
  CircuitPainter(
    this.project, {
    this.selected,
    this.wireStart,
    this.result,
    this.selectedWire,
    this.viewScale = 1,
    this.lightCanvas = false,
    this.wirePreview,
  });
  final Map<String, dynamic> project;
  final String? selected, wireStart;
  final Map<String, dynamic>? result;
  final int? selectedWire;
  final double viewScale;
  final bool lightCanvas;
  final Offset? wirePreview;
  Color get background =>
      lightCanvas ? const Color(0xfff7f7f3) : const Color(0xff0b1215);
  Color get ink =>
      lightCanvas ? const Color(0xff343a40) : const Color(0xffd3e4df);
  double get zoom => viewScale.clamp(.08, 5);
  void text(
    Canvas canvas,
    String value,
    Offset at, {
    Color? color,
    double size = 12,
    bool center = false,
    bool mask = true,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color ?? ink,
          fontSize: size / zoom,
          fontWeight: FontWeight.w600,
          fontFamily: 'SCMono',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final topLeft = at - Offset(center ? p.width / 2 : 0, 0);
    if (mask) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (topLeft & p.size).inflate(3 / zoom),
          Radius.circular(3 / zoom),
        ),
        Paint()..color = background.withValues(alpha: .94),
      );
    }
    p.paint(canvas, topLeft);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(background, BlendMode.src);
    final grid = Paint()
      ..color = lightCanvas ? const Color(0xffd3d5d1) : const Color(0xff263338)
      ..strokeWidth = 1.25 / zoom
      ..strokeCap = StrokeCap.round;
    final visible = canvas.getLocalClipBounds();
    final step = zoom < .3
        ? 96.0
        : zoom < .6
        ? 48.0
        : 24.0;
    final points = <Offset>[];
    for (
      double x = (visible.left / step).floor() * step;
      x <= visible.right;
      x += step
    ) {
      for (
        double y = (visible.top / step).floor() * step;
        y <= visible.bottom;
        y += step
      ) {
        points.add(Offset(x, y));
      }
    }
    canvas.drawPoints(ui.PointMode.points, points, grid);
    final wp = Paint()
      ..strokeWidth = 2 / zoom
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final wires = wiresOf(project);
    for (int i = 0; i < wires.length; i++) {
      final w = wires[i],
          a = terminalPosition(project, w['from'] as String),
          b = terminalPosition(project, w['to'] as String);
      if (a == null || b == null) continue;
      final corner = wireCorner(project, w['from'] as String, a, b);
      wp.color = i == selectedWire
          ? const Color(0xffef8b36)
          : result != null
          ? const Color(0xff8daf9f)
          : lightCanvas
          ? const Color(0xff66717a)
          : const Color(0xff72918e);
      canvas.drawPath(schematicPolyline([a, corner, b], 5 / zoom), wp);
    }
    if (wireStart != null && wirePreview != null) {
      final a = terminalPosition(project, wireStart!);
      if (a != null) {
        final corner = wireCorner(project, wireStart!, a, wirePreview!);
        canvas.drawPath(
          schematicPolyline([a, corner, wirePreview!], 5 / zoom),
          wp..color = const Color(0xffe29742),
        );
      }
    }
    final rows = (result?['components'] as List?) ?? [];
    for (final c in componentsOf(project)) {
      final type = c['type'] as String, active = c['id'] == selected;
      final center = Offset(
            (c['x'] as num).toDouble(),
            (c['y'] as num).toDouble(),
          ),
          angle = (c['rotation'] as num? ?? 0) * math.pi / 180;
      Map<String, dynamic>? reading;
      for (final r in rows) {
        if (r['id'] == c['id']) {
          reading = r as Map<String, dynamic>;
          break;
        }
      }
      if (type == 'led' && ((reading?['current'] as num?) ?? 0) > .00001) {
        canvas.drawCircle(
          center,
          31,
          Paint()..color = const Color(0xffffbd48).withValues(alpha: .22),
        );
        canvas.drawCircle(
          center,
          22,
          Paint()..color = const Color(0xffffbd48).withValues(alpha: .15),
        );
      }
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      if (active) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: 124,
            height: pinCount(type) == 3 ? 124 : 74,
          ),
          const Radius.circular(12),
        );
        canvas.drawRRect(
          rect,
          Paint()..color = const Color(0xffaace69).withValues(alpha: .09),
        );
        canvas.drawRRect(
          rect,
          Paint()
            ..color = const Color(0xffaace69)
            ..strokeWidth = 1.5 / zoom
            ..style = PaintingStyle.stroke,
        );
      }
      final pen = Paint()
        ..color = active ? const Color(0xffaace69) : ink
        ..strokeWidth = 2.1 / zoom
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      drawCircuitSymbol(canvas, type, (c['value'] as num).toDouble(), pen);
      canvas.restore();
      if (zoom > .28 || active) {
        final vertical = (c['rotation'] as num? ?? 0) % 180 == 90,
            side = type == 'npn' || type == 'pnp';
        final label =
            center +
            (side
                ? Offset(math.max(53, 32 + 12 / zoom), -16 / zoom)
                : Offset(
                    vertical ? math.max(42, 25 + 12 / zoom) : 0,
                    vertical
                        ? -16 / zoom
                        : type == 'ground'
                        ? -30 / zoom
                        : -18 - 38 / zoom,
                  ));
        text(
          canvas,
          c['label'] as String,
          label,
          center: !vertical && !side,
          color: active ? const Color(0xffaace69) : ink,
        );
        if (type != 'ground') {
          text(
            canvas,
            componentValue(c),
            label + Offset(0, 19 / zoom),
            size: 10.5,
            center: !vertical && !side,
            color: lightCanvas
                ? const Color(0xff65768e)
                : const Color(0xff9bb2aa),
          );
        }
        if (reading != null) {
          text(
            canvas,
            engineering(reading['voltage'] as num, 'V'),
            vertical || side
                ? label + Offset(0, 38 / zoom)
                : center + Offset(0, 18 + 12 / zoom),
            size: 10.5,
            center: !vertical,
            color: const Color(0xffaace69),
          );
        }
      }
      for (int k = 0; k < pinCount(type); k++) {
        final pos = pinPosition(c, k), pending = wireStart == '${c['id']}:$k';
        canvas.drawCircle(
          pos,
          4.5 / zoom,
          Paint()..color = pending ? const Color(0xffed9d43) : background,
        );
        canvas.drawCircle(
          pos,
          4.5 / zoom,
          Paint()
            ..color = pending
                ? const Color(0xffed9d43)
                : const Color(0xff648294)
            ..strokeWidth = 1.5 / zoom
            ..style = PaintingStyle.stroke,
        );
        if (active && type != 'ground') {
          text(
            canvas,
            pinNames(type)[k],
            pos + Offset(7 / zoom, 6 / zoom),
            size: 8.5,
            mask: false,
            color: lightCanvas ? const Color(0xff56718b) : muted,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CircuitPainter old) => true;
}

class ResultChart extends CustomPainter {
  final List<Map<String, dynamic>> samples;
  final String component;
  final String metric;
  String get unit => metric == 'current'
      ? 'A'
      : metric == 'power'
      ? 'W'
      : 'V';
  ResultChart(this.samples, this.component, {this.metric = 'voltage'});
  void label(Canvas canvas, String text, Offset at, {bool right = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 9, color: muted, fontFamily: 'SCMono'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at - Offset(right ? painter.width : 0, 0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2 || size.width < 90) return;
    final values = samples
        .map(
          (s) =>
              ((s['components'] as List).firstWhere(
                        (c) => c['id'] == component,
                      )[metric]
                      as num)
                  .toDouble(),
        )
        .toList();
    final peak = math.max(
      values.reduce(math.max).abs(),
      values.reduce(math.min).abs(),
    );
    final padding = math.max(peak * .1, 1e-12);
    final high = math.max(0.0, values.reduce(math.max)) + padding;
    final low = math.min(0.0, values.reduce(math.min)) - padding;
    final plot = Rect.fromLTRB(47, 8, size.width - 8, size.height - 24);
    final start = (samples.first['time'] as num).toDouble(),
        end = (samples.last['time'] as num).toDouble();
    if (end <= start || plot.height <= 0) return;
    final grid = Paint()
      ..color = edge
      ..strokeWidth = 1;
    for (int k = 0; k <= 3; k++) {
      final y = plot.top + k * plot.height / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      label(
        canvas,
        engineering(high - k * (high - low) / 3, unit),
        Offset(plot.left - 6, y - 5),
        right: true,
      );
    }
    label(canvas, engineering(start, 's'), Offset(plot.left, plot.bottom + 7));
    label(
      canvas,
      engineering(end, 's'),
      Offset(plot.right, plot.bottom + 7),
      right: true,
    );
    final path = Path();
    for (int k = 0; k < values.length; k++) {
      final time = (samples[k]['time'] as num).toDouble();
      final point = Offset(
        plot.left + (time - start) / (end - start) * plot.width,
        plot.bottom - (values[k] - low) / (high - low) * plot.height,
      );
      if (k == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.save();
    canvas.clipRect(plot);
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ResultChart oldDelegate) => true;
}
