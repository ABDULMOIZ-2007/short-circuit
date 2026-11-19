import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'project_view.dart';

const canvasDark = Color(0xff0b1215),
    surfaceDeep = Color(0xff10191d),
    softWhite = Color(0xffe7f0e9);
TextStyle technical({
  double size = 10,
  Color color = muted,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: 'SCMono',
  fontSize: size,
  color: color,
  fontWeight: weight,
);
Color partColor(String type) => componentCategories[type] == 'Sources'
    ? const Color(0xfff1c67a)
    : componentCategories[type] == 'Semiconductors'
    ? const Color(0xffc1a2ec)
    : const Color(0xff92c9d7);

class LabLogo extends StatelessWidget {
  const LabLogo({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LogoPainter());
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 32);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 32, 32),
        const Radius.circular(9),
      ),
      Paint()..color = accent,
    );
    final p = Paint()
      ..color = canvasDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    c.drawPath(
      Path()
        ..moveTo(23, 9)
        ..lineTo(12, 9)
        ..lineTo(8, 13)
        ..lineTo(8, 16)
        ..lineTo(20, 16)
        ..lineTo(24, 20)
        ..lineTo(24, 23)
        ..lineTo(10, 23),
      p,
    );
    c.drawCircle(const Offset(23, 9), 1.9, Paint()..color = canvasDark);
    c.drawCircle(const Offset(10, 23), 1.9, Paint()..color = canvasDark);
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => false;
}

class LabSurface extends StatelessWidget {
  const LabSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = panel,
    this.radius = 16,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final double radius;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: const BorderSide(color: edge),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class LabSection extends StatelessWidget {
  const LabSection(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 3, height: 12, color: accent),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label.toUpperCase(),
          style: technical(size: 10, color: softWhite),
        ),
      ),
      ?trailing,
    ],
  );
}

class LabMetric extends StatelessWidget {
  const LabMetric(this.label, this.value, {super.key, this.color = softWhite});
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label.toUpperCase(), style: technical(size: 9)),
      const SizedBox(height: 7),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'SCMono',
          fontSize: 17,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    ],
  );
}

class CircuitPreview extends StatefulWidget {
  const CircuitPreview(this.name, {super.key});
  final String name;
  @override
  State<CircuitPreview> createState() => _CircuitPreviewState();
}

class _CircuitPreviewState extends State<CircuitPreview> {
  static final parsed = <String, Map<String, dynamic>>{};
  late final Future<Map<String, dynamic>> data = load();
  Future<Map<String, dynamic>> load() async {
    final cached = parsed[widget.name];
    if (cached != null) return cached;
    final value =
        jsonDecode(
              await rootBundle.loadString('examples/${widget.name}.sc.json'),
            )
            as Map<String, dynamic>;
    parsed[widget.name] = value;
    return value;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: data,
    builder: (context, snapshot) => Semantics(
      label: snapshot.hasData
          ? '${snapshot.data!['title']} schematic preview'
          : 'Loading schematic preview',
      child: CustomPaint(
        painter: _PreviewPainter(snapshot.data),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.project);
  final Map<String, dynamic>? project;
  @override
  void paint(Canvas c, Size s) {
    final grid = Paint()
      ..color = const Color(0xff293b3b)
      ..strokeWidth = 1.2;
    for (double x = 8; x < s.width; x += 16) {
      for (double y = 8; y < s.height; y += 16) {
        c.drawCircle(Offset(x, y), .55, grid);
      }
    }
    if (project == null) return;
    final parts = componentsOf(project!);
    if (parts.isEmpty) return;
    final minX =
            parts.map((p) => (p['x'] as num).toDouble()).reduce(math.min) - 65,
        maxX =
            parts.map((p) => (p['x'] as num).toDouble()).reduce(math.max) + 65;
    final minY =
            parts.map((p) => (p['y'] as num).toDouble()).reduce(math.min) - 65,
        maxY =
            parts.map((p) => (p['y'] as num).toDouble()).reduce(math.max) + 85;
    final scale = math.min(
      (s.width - 22) / (maxX - minX),
      (s.height - 16) / (maxY - minY),
    );
    c.save();
    c.translate(
      (s.width - (maxX - minX) * scale) / 2 - minX * scale,
      (s.height - (maxY - minY) * scale) / 2 - minY * scale,
    );
    c.scale(scale);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xff507168);
    for (final w in wiresOf(project!)) {
      final a = terminalPosition(project!, w['from'] as String),
          b = terminalPosition(project!, w['to'] as String);
      if (a == null || b == null) continue;
      final corner = wireCorner(project!, w['from'] as String, a, b);
      c.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(b.dx, b.dy),
        pen,
      );
    }
    pen.color = const Color(0xffc6e2b8);
    pen.strokeWidth = 1.4 / scale;
    for (final part in parts) {
      c.save();
      c.translate((part['x'] as num).toDouble(), (part['y'] as num).toDouble());
      c.rotate((part['rotation'] as num) * math.pi / 180);
      drawCircuitSymbol(
        c,
        part['type'] as String,
        (part['value'] as num).toDouble(),
        pen,
      );
      c.restore();
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) => old.project != project;
}

class NodeVoltagePlot extends CustomPainter {
  NodeVoltagePlot(this.nodes);
  final List<dynamic> nodes;
  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final values = nodes.map((n) => (n['voltage'] as num).toDouble()).toList();
    final low = math.min(0.0, values.reduce(math.min)),
        high = math.max(1e-12, values.reduce(math.max)),
        left = 36.0,
        right = size.width - 60,
        width = right - left;
    final zero = left - low / (high - low) * width;
    void text(String value, Offset at, Color color) {
      final p = TextPainter(
        text: TextSpan(
          text: value,
          style: technical(size: 10, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, at);
    }

    canvas.drawLine(
      Offset(zero, 3),
      Offset(zero, size.height - 3),
      Paint()..color = edge,
    );
    final height = size.height / nodes.length;
    for (int i = 0; i < nodes.length; i++) {
      final y = (i + .5) * height,
          end = left + (values[i] - low) / (high - low) * width;
      text(nodes[i]['name'] as String, Offset(0, y - 6), muted);
      final rect = Rect.fromLTRB(
        math.min(zero, end),
        y - 3,
        math.max(zero, end).clamp(zero + 1, double.infinity),
        y + 3,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = accent.withValues(alpha: .7),
      );
      text(engineering(values[i], 'V'), Offset(right + 10, y - 6), softWhite);
    }
  }

  @override
  bool shouldRepaint(covariant NodeVoltagePlot old) => old.nodes != nodes;
}
