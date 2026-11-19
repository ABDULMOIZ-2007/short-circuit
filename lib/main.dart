import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:short_circuit_core/short_circuit_core.dart';

import 'project_view.dart';
import 'component_editor.dart';
import 'component_library.dart';
import 'current_flow.dart';
import 'design_system.dart';

Future<Map<String, dynamic>> dispatchNative(Map<String, dynamic> data) =>
    Isolate.run(() => executeNative(data));

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShortCircuitApp());
}

const exampleCatalog = <String, List<String>>{
  'divider': ['Voltage divider', '12 V · 1 kΩ + 2 kΩ', 'resistor'],
  'parallel': ['Parallel branches', 'Two paths for current', 'resistor'],
  'rc': ['RC charging', 'Capacitor step response', 'capacitor'],
  'rl': ['RL step response', 'Watch inductor current rise', 'inductor'],
  'led': ['Light an LED', 'Forward voltage & current', 'led'],
  'zener': ['Zener regulator', 'Reverse breakdown at 5.1 V', 'zener'],
  'switch': ['Switch a circuit', 'Double-tap the switch to toggle', 'switch'],
  'potentiometer': [
    'Adjustable divider',
    'Edit the wiper position',
    'potentiometer',
  ],
  'npn': ['NPN transistor', 'Base current controls collector current', 'npn'],
};

ThemeData shortCircuitTheme() => ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  fontFamily: 'SpaceGrotesk',
  scaffoldBackgroundColor: canvasDark,
  colorScheme: const ColorScheme.dark(
    primary: accent,
    onPrimary: canvasDark,
    secondary: Color(0xfff1c67a),
    surface: panel,
    onSurface: softWhite,
    outline: edge,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: canvasDark,
    surfaceTintColor: Colors.transparent,
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: surfaceDeep,
    showDragHandle: true,
    dragHandleColor: edge,
    dragHandleSize: Size(30, 3),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(foregroundColor: softWhite),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: canvasDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(
        fontFamily: 'SpaceGrotesk',
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: softWhite,
      side: const BorderSide(color: edge),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: canvasDark,
    labelStyle: const TextStyle(color: muted, fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: edge),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: edge),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: accent),
    ),
  ),
  dividerTheme: const DividerThemeData(color: edge, thickness: 1),
);

class ShortCircuitApp extends StatelessWidget {
  const ShortCircuitApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Short Circuit',
    debugShowCheckedModeBanner: false,
    theme: shortCircuitTheme(),
    home: const Workbench(),
  );
}

class Workbench extends StatefulWidget {
  const Workbench({super.key, this.nativeRequest, this.projectDirectory});
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
  nativeRequest;
  final String? projectDirectory;
  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Map<String, dynamic> project = {
    'schema': 1,
    'id': 'untitled',
    'title': 'Untitled circuit',
    'components': <dynamic>[],
    'wires': <dynamic>[],
  };
  final undo = <Map<String, dynamic>>[], redo = <Map<String, dynamic>>[];
  final transform = TransformationController();
  Map<String, dynamic>? result, transient;
  String? selected, wireStart, dragId;
  int? selectedWire;
  String tool = 'select', analysis = 'simulate', error = '', directory = '';
  bool busy = false, ready = false, dirty = false, dragMoved = false;
  Map<String, dynamic>? dragBefore;
  Offset? dragStart, componentStart;
  final duration = TextEditingController(text: '50');
  Future<void> pending = Future<void>.value();
  Size? previousCanvasSize;
  int screen = 0, revision = 0;
  Timer? checkpointTimer;
  late final AnimationController flowClock;
  bool flowPlaying = true, appActive = true, reducedMotion = false;
  bool shelfLoading = false;
  List<Map<String, dynamic>> savedProjects = [];
  String shelfError = '';
  String? chartComponent;
  String chartMetric = 'voltage';
  double flowSpeed = 1;
  bool lightCanvas = false, wireDragging = false, wireMoved = false;
  Offset? wirePreview, lastDoubleTap;
  final pointers = <int>{};
  String get observedCapacitor {
    final eligible = componentsOf(
      project,
    ).where((c) => c['type'] != 'ground').toList();
    if (eligible.any((c) => c['id'] == chartComponent)) return chartComponent!;
    final reactive = eligible.where(
      (c) => ['capacitor', 'inductor'].contains(c['type']),
    );
    return (reactive.isNotEmpty ? reactive.first : eligible.first)['id']
        as String;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    flowClock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reducedMotion = MediaQuery.disableAnimationsOf(context);
    syncFlowAnimation();
  }

  void syncFlowAnimation() {
    final hasCurrent = (result?['components'] as List? ?? []).any(
      (row) =>
          CurrentFlowPainter.carriesCurrent(row['current']) ||
          (row['terminalCurrents'] as List? ?? []).any(
            CurrentFlowPainter.carriesCurrent,
          ),
    );
    final animate =
        hasCurrent &&
        mounted &&
        appActive &&
        screen == 0 &&
        result != null &&
        flowPlaying &&
        !busy &&
        !reducedMotion;
    if (animate && !flowClock.isAnimating) {
      flowClock.repeat();
    }
    if (!animate && flowClock.isAnimating) {
      flowClock.stop();
    }
  }

  void toggleCurrentFlow() {
    setState(() => flowPlaying = !flowPlaying);
    syncFlowAnimation();
  }

  void setFlowSpeed(double speed) {
    flowClock.stop();
    flowClock.duration = Duration(milliseconds: (10000 / speed).round());
    setState(() => flowSpeed = speed);
    syncFlowAnimation();
  }

  Future<void> initialize() async {
    try {
      if (widget.projectDirectory != null) {
        directory = widget.projectDirectory!;
      } else {
        final base = await getApplicationSupportDirectory();
        directory = '${base.path}/short-circuit-projects';
        await Directory(directory).create(recursive: true);
      }
      var data =
          jsonDecode(await rootBundle.loadString('examples/divider.sc.json'))
              as Map<String, dynamic>;
      var recovered = false;
      try {
        final last = await request({'op': 'restore'});
        if (last['project'] is Map<String, dynamic>) {
          data = last['project'] as Map<String, dynamic>;
          recovered = last['dirty'] == true;
        }
      } catch (e) {
        error = 'Workspace recovery failed: $e';
      }
      if (!mounted) return;
      setState(() {
        project = data;
        selected = null;
        dirty = recovered;
        ready = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Startup failed: $e';
          ready = true;
        });
      }
    }
  }

  @override
  void dispose() {
    checkpointTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    flowClock.dispose();
    duration.dispose();
    transform.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appActive = state == AppLifecycleState.resumed;
    syncFlowAnimation();
    if (state != AppLifecycleState.resumed && ready) {
      checkpointTimer?.cancel();
      checkpoint();
    }
  }

  Future<void> checkpoint() async {
    if (!ready || directory.isEmpty) return;
    try {
      await request({
        'op': 'checkpoint',
        'project': copyProject(project),
        'dirty': dirty,
      });
    } catch (e) {
      if (mounted) toast('Workspace recovery could not be saved: $e');
    }
  }

  void scheduleCheckpoint() {
    revision++;
    checkpointTimer?.cancel();
    checkpointTimer = Timer(const Duration(milliseconds: 650), checkpoint);
  }

  Future<Map<String, dynamic>> request(Map<String, dynamic> payload) {
    final data = {...payload, 'directory': directory};
    final future = pending.then(
      (_) => widget.nativeRequest != null
          ? widget.nativeRequest!(data)
          : dispatchNative(data),
    );
    pending = future.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return future;
  }

  void toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  void snapshot() {
    undo.add(copyProject(project));
    if (undo.length > 60) undo.removeAt(0);
    redo.clear();
  }

  void clearResults() {
    flowClock.stop();
    result = null;
    transient = null;
    error = '';
    dirty = true;
    scheduleCheckpoint();
  }

  void mutate(VoidCallback action) {
    if (busy) return;
    setState(() {
      snapshot();
      action();
      clearResults();
    });
  }

  Map<String, dynamic>? get selectedComponent {
    for (final c in componentsOf(project)) {
      if (c['id'] == selected) return c;
    }
    return null;
  }

  Future<void> loadExample(String name) async {
    final data =
        jsonDecode(await rootBundle.loadString('examples/$name.sc.json'))
            as Map<String, dynamic>;
    if (!mounted) return;
    mutate(() {
      project = data;
      previousCanvasSize = null;
      selected = null;
      selectedWire = null;
      wireStart = null;
      analysis = ['rc', 'rl'].contains(name) ? 'transient' : 'simulate';
    });
  }

  void add(String type) {
    if (componentsOf(project).length >= 128) {
      toast('Limit: 128 components.');
      return;
    }
    const prefix = componentPrefixes;
    const values = componentDefaults;
    int n = 1;
    while (componentsOf(project).any((c) => c['id'] == '${prefix[type]}$n')) {
      n++;
    }
    final id = '${prefix[type]}$n', count = componentsOf(project).length;
    final viewport = previousCanvasSize ?? const Size(720, 440);
    final center = transform.toScene(
      Offset(viewport.width / 2, viewport.height / 2),
    );
    mutate(() {
      componentsOf(project).add({
        'id': id,
        'label': type == 'ground' ? 'GND' : id,
        'type': type,
        'value': values[type],
        if (type == 'potentiometer') 'setting': .5,
        'x': ((center.dx / 24).round() * 24 + (count % 3) * 24).clamp(
          48,
          worldWidth - 48,
        ),
        'y': ((center.dy / 24).round() * 24 + (count % 3) * 24).clamp(
          48,
          worldHeight - 48,
        ),
        'rotation': type == 'voltage' || type == 'current' ? 90 : 0,
      });
      selected = id;
      selectedWire = null;
      tool = 'select';
      wireStart = null;
    });
  }

  void remove() {
    if (selected == null && selectedWire == null) return;
    mutate(() {
      if (selected != null) {
        (project['components'] as List).removeWhere((c) => c['id'] == selected);
        (project['wires'] as List).removeWhere(
          (w) =>
              (w['from'] as String).split(':')[0] == selected ||
              (w['to'] as String).split(':')[0] == selected,
        );
      } else if (selectedWire != null) {
        (project['wires'] as List).removeAt(selectedWire!);
      }
      selected = null;
      selectedWire = null;
      wireStart = null;
    });
  }

  void rotate() {
    final c = selectedComponent;
    if (c == null || c['type'] == 'ground') return;
    mutate(() => c['rotation'] = ((c['rotation'] as num? ?? 0) + 90) % 360);
  }

  void duplicate() {
    final c = selectedComponent;
    if (c == null) return;
    final data = Map<String, dynamic>.from(c);
    add(c['type'] as String);
    final copy = selectedComponent;
    if (copy == null) return;
    setState(() {
      final id = copy['id'];
      copy.addAll(data);
      copy['id'] = id;
      copy['label'] = id;
      copy['x'] = math.min(worldWidth - 48, (data['x'] as num) + 72);
      copy['y'] = math.min(worldHeight - 48, (data['y'] as num) + 72);
    });
  }

  void history(bool back) {
    final source = back ? undo : redo, target = back ? redo : undo;
    if (source.isEmpty) return;
    setState(() {
      target.add(copyProject(project));
      project = source.removeLast();
      selected = null;
      selectedWire = null;
      wireStart = null;
      clearResults();
    });
  }

  Future<void> run() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    syncFlowAnimation();
    try {
      final ms = double.tryParse(duration.text);
      if (analysis == 'transient' &&
          (ms == null || !ms.isFinite || ms <= 0 || ms > 3600000)) {
        throw const FormatException(
          'Enter a duration greater than 0 and at most 3600000 ms.',
        );
      }
      final response = await request({
        'op': analysis,
        'project': copyProject(project),
        'duration': (ms ?? 50) / 1000,
        'steps': 200,
      });
      if (!mounted) return;
      setState(() {
        transient = analysis == 'transient'
            ? response['result'] as Map<String, dynamic>
            : null;
        result = transient == null
            ? response['result'] as Map<String, dynamic>
            : (transient!['samples'] as List).last as Map<String, dynamic>;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          screen = 1;
          result = null;
          transient = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        syncFlowAnimation();
      }
    }
  }

  Future<void> save() async {
    if (busy || !ready) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TextEntryDialog(
        title: 'Save circuit',
        initialText: project['title'] as String,
        label: 'Project name',
        action: 'Save',
        maxLength: 80,
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      project['title'] = name;
      dirty = true;
      if (!(project['id'] as String).startsWith('p-')) {
        project['id'] = 'p-${DateTime.now().millisecondsSinceEpoch}';
      }
    });
    scheduleCheckpoint();
    final savedRevision = revision;
    try {
      await request({'op': 'save', 'project': copyProject(project)});
      if (mounted) {
        if (revision == savedRevision) setState(() => dirty = false);
        await checkpoint();
        await refreshShelf();
        toast('Project saved on this device.');
      }
    } catch (e) {
      toast('Save failed: $e');
    }
  }

  Future<void> examples() async {
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Starter circuits'),
        children: [
          for (final e in exampleCatalog.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SymbolPreview(e.value[2], size: 36),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.value[0]),
                          const SizedBox(height: 3),
                          Text(
                            e.value[1],
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (key != null) {
      await loadExample(key);
      if (mounted) navigate(0);
    }
  }

  Future<void> newProject() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new circuit?'),
        content: const Text(
          'Save or export your current work first if you want to keep it. You can return to it with Undo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (yes == true) {
      mutate(() {
        screen = 0;
        analysis = 'simulate';
        previousCanvasSize = null;
        project = {
          'schema': 1,
          'id': 'p-${DateTime.now().millisecondsSinceEpoch}',
          'title': 'Untitled circuit',
          'components': <dynamic>[],
          'wires': <dynamic>[],
        };
        selected = null;
        selectedWire = null;
        wireStart = null;
      });
    }
  }

  Future<void> exportProject() async {
    final data = const JsonEncoder.withIndent('  ').convert(project);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export project JSON'),
        content: SizedBox(
          width: 500,
          height: 350,
          child: SingleChildScrollView(
            child: SelectableText(
              data,
              style: const TextStyle(fontFamily: 'SCMono', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: data));
              toast('Project JSON copied.');
            },
            child: const Text('Copy JSON'),
          ),
        ],
      ),
    );
  }

  Future<void> importProject() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _TextEntryDialog(
        title: 'Import project JSON',
        label: 'Paste your exported project here',
        action: 'Import',
        maxLines: 10,
      ),
    );
    if (text == null) return;
    try {
      if (text.length > 2097152) {
        throw const FormatException('Project exceeds 2 MB.');
      }
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['schema'] != 1 ||
          data['title'] is! String ||
          data['id'] is! String ||
          !RegExp(r'^[\w-]{1,64}$').hasMatch(data['id'] as String) ||
          componentsOf(data).length > 128 ||
          wiresOf(data).length > 512) {
        throw const FormatException('Invalid project.');
      }
      final terminals = <String>{}, ids = <String>{};
      for (final c in componentsOf(data)) {
        if (!componentNames.containsKey(c['type']) ||
            c['id'] is! String ||
            !RegExp(r'^[\w-]{1,64}$').hasMatch(c['id'] as String) ||
            !ids.add(c['id'] as String) ||
            c['label'] is! String ||
            c['value'] is! num ||
            (c['value'] as num).isFinite == false) {
          throw const FormatException('Invalid component.');
        }
        for (final k in ['x', 'y', 'rotation']) {
          if (c[k] is! num || !(c[k] as num).isFinite) {
            throw const FormatException('Invalid position.');
          }
        }
        if ((c['rotation'] as num) % 90 != 0) {
          throw const FormatException('Rotation must be a multiple of 90.');
        }
        c['x'] = (c['x'] as num).clamp(48, worldWidth - 48);
        c['y'] = (c['y'] as num).clamp(48, worldHeight - 48);
        final invalidValue = validateComponentValue(
          c['type'] as String,
          (c['value'] as num).toDouble(),
        );
        if (invalidValue != null) throw FormatException(invalidValue);
        if (c['type'] == 'potentiometer' &&
            c.containsKey('setting') &&
            (c['setting'] is! num ||
                !(c['setting'] as num).isFinite ||
                (c['setting'] as num) < 0 ||
                (c['setting'] as num) > 1)) {
          throw const FormatException(
            'Wiper position must be between 0 and 1.',
          );
        }
        for (var pin = 0; pin < pinCount(c['type'] as String); pin++) {
          terminals.add('${c['id']}:$pin');
        }
      }
      for (final w in wiresOf(data)) {
        if (!terminals.contains(w['from']) || !terminals.contains(w['to'])) {
          throw const FormatException('Wire points to a missing terminal.');
        }
      }
      if (mounted) {
        mutate(() {
          project = data;
          selected = null;
          selectedWire = null;
          wireStart = null;
        });
      }
    } catch (e) {
      toast('Import failed: $e');
    }
  }

  Future<void> showGuide() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Editor help'),
      content: const SingleChildScrollView(
        child: Text(
          '1. Tap + to open the component library. Search or filter 13 parts. A new part appears in the middle of your view.\n\n'
          '2. Select moves parts. Double-tap a part to edit its value. Double-tap a switch to open or close it.\n\n'
          '3. Use Wire to tap two pins or drag between them. In Select, tapping two pins also connects them. Wire crossings do not form junctions.\n\n'
          '4. Pinch to zoom. Pan moves the view. + and − zoom around the centre; Fit brings your whole circuit into view.\n\n'
          '5. Connect ground to the return path and tap Run. Results supports DC and transient analysis. Transient starts capacitors at 0 V and inductors at 0 A; sources turn on at t = 0.\n\n'
          'Values accept SI prefixes: 4.7k = 4700 Ω, 10u = 10 µF, 10m = 10 mH. Potentiometers have A, B and wiper pins; transistors have C, E and B pins.\n\n'
          'Save keeps a named project on this device. Draft recovery runs automatically. Projects contains nine starter circuits. JSON import/export uses the clipboard.',
          style: TextStyle(height: 1.5),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
  String? hitPin(Offset p) {
    var nearest = (18 / transform.value.getMaxScaleOnAxis()).clamp(12.0, 28.0);
    String? terminal;
    for (final c in componentsOf(project).reversed) {
      for (int k = 0; k < pinCount(c['type'] as String); k++) {
        final distance = (p - pinPosition(c, k)).distance;
        if (distance < nearest) {
          nearest = distance;
          terminal = '${c['id']}:$k';
        }
      }
    }
    return terminal;
  }

  String? hitComponent(Offset p) {
    for (final c in componentsOf(project).reversed) {
      if ((p - Offset((c['x'] as num).toDouble(), (c['y'] as num).toDouble()))
              .distance <
          56) {
        return c['id'] as String;
      }
    }
    return null;
  }

  double segmentDistance(Offset p, Offset a, Offset b) {
    final d = b - a, l = d.distanceSquared;
    if (l == 0) return (p - a).distance;
    final t = (((p - a).dx * d.dx + (p - a).dy * d.dy) / l).clamp(0.0, 1.0);
    return (p - (a + d * t)).distance;
  }

  int? hitWire(Offset p) {
    final wires = wiresOf(project);
    for (int i = wires.length - 1; i >= 0; i--) {
      final w = wires[i],
          a = terminalPosition(project, w['from'] as String),
          b = terminalPosition(project, w['to'] as String);
      if (a == null || b == null) continue;
      final corner = wireCorner(project, w['from'] as String, a, b);
      if (math.min(
            segmentDistance(p, a, corner),
            segmentDistance(p, corner, b),
          ) <
          10) {
        return i;
      }
    }
    return null;
  }

  void tapCanvas(TapUpDetails details) {
    if (busy) return;
    final p = details.localPosition;
    final body = hitComponent(p);
    if (tool == 'select' && body != null) {
      final c = componentsOf(project).firstWhere((c) => c['id'] == body);
      if ((p - Offset((c['x'] as num).toDouble(), (c['y'] as num).toDouble()))
              .distance <
          30) {
        setState(() {
          selected = body;
          selectedWire = null;
        });
        return;
      }
    }
    final t = tool == 'pan' ? null : hitPin(p);
    if (tool == 'pan') return;
    if (t != null) {
      if (wireStart != null && wireStart != t) {
        final exists = wiresOf(project).any(
          (w) =>
              (w['from'] == wireStart && w['to'] == t) ||
              (w['to'] == wireStart && w['from'] == t),
        );
        if (!exists) {
          if (wiresOf(project).length >= 512) {
            toast('Limit: 512 wires.');
            return;
          }
          mutate(() => wiresOf(project).add({'from': wireStart, 'to': t}));
        }
        setState(() => wireStart = null);
      } else {
        setState(() {
          wireStart = t;
          tool = 'wire';
        });
      }
    } else {
      setState(() {
        selected = hitComponent(p);
        selectedWire = selected == null ? hitWire(p) : null;
      });
    }
  }

  void startDrag(DragStartDetails d) {
    if (busy || tool != 'select' || hitPin(d.localPosition) != null) return;
    dragId = hitComponent(d.localPosition);
    if (dragId == null) return;
    final c = componentsOf(project).firstWhere((c) => c['id'] == dragId);
    dragBefore = copyProject(project);
    dragStart = d.localPosition;
    componentStart = Offset(
      (c['x'] as num).toDouble(),
      (c['y'] as num).toDouble(),
    );
    dragMoved = false;
    setState(() => selected = dragId);
  }

  void updateDrag(DragUpdateDetails d) {
    if (dragId == null) return;
    final delta = d.localPosition - dragStart!;
    if (delta.distance < 3 && !dragMoved) return;
    dragMoved = true;
    final c = componentsOf(project).firstWhere((c) => c['id'] == dragId),
        p = componentStart! + delta;
    setState(() {
      c['x'] = ((p.dx / 24).round() * 24).clamp(48, worldWidth - 48);
      c['y'] = ((p.dy / 24).round() * 24).clamp(48, worldHeight - 48);
    });
  }

  void endDrag() {
    if (dragMoved && dragBefore != null) {
      setState(() {
        undo.add(dragBefore!);
        if (undo.length > 60) undo.removeAt(0);
        redo.clear();
        clearResults();
      });
    }
    dragId = null;
    dragMoved = false;
    dragBefore = null;
  }

  Widget toolButton(
    IconData icon,
    String tooltip,
    VoidCallback? action, {
    bool active = false,
  }) => IconButton(
    onPressed: busy ? null : action,
    tooltip: tooltip,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: Icon(icon, size: 21, color: active ? accent : muted),
  );
  Widget box(Widget child) => Material(
    color: panel,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: edge),
      borderRadius: BorderRadius.circular(5),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
  void fitCanvas(Size size) {
    final parts = componentsOf(project);
    double minX = 180, minY = 120, maxX = 820, maxY = 580;
    if (parts.isNotEmpty) {
      minX =
          parts.map((c) => (c['x'] as num).toDouble()).reduce(math.min) - 110;
      maxX =
          parts.map((c) => (c['x'] as num).toDouble()).reduce(math.max) + 110;
      minY = parts.map((c) => (c['y'] as num).toDouble()).reduce(math.min) - 95;
      maxY = parts.map((c) => (c['y'] as num).toDouble()).reduce(math.max) + 95;
    }
    final usable = Rect.fromLTWH(
      22,
      45,
      math.max(100, size.width - 44),
      math.max(100, size.height - 150),
    );
    final scale = math
        .min(usable.width / (maxX - minX), usable.height / (maxY - minY))
        .clamp(.12, 1.35);
    transform.value = Matrix4.identity()
      ..translateByDouble(
        usable.center.dx - (minX + maxX) / 2 * scale,
        usable.center.dy - (minY + maxY) / 2 * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void zoomCanvas(double factor) {
    final size = previousCanvasSize;
    if (size == null) return;
    final center = Offset(size.width / 2, size.height / 2),
        scene = transform.toScene(center);
    final scale = (transform.value.getMaxScaleOnAxis() * factor).clamp(
      .12,
      4.0,
    );
    transform.value = Matrix4.identity()
      ..translateByDouble(
        center.dx - scene.dx * scale,
        center.dy - scene.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void changeTool(String next) {
    HapticFeedback.selectionClick();
    setState(() {
      tool = next;
      wireStart = null;
      wirePreview = null;
    });
  }

  void scenePointerDown(PointerDownEvent e) {
    if (busy) return;
    pointers.add(e.pointer);
    if (pointers.length > 1) {
      if (dragBefore != null) {
        setState(() => project = dragBefore!);
        dragId = null;
        dragBefore = null;
        dragMoved = false;
      }
      wireDragging = false;
      wirePreview = null;
      return;
    }
    if (tool == 'select') {
      startDrag(
        DragStartDetails(
          localPosition: e.localPosition,
          globalPosition: e.position,
        ),
      );
    }
    if (tool == 'wire') {
      final pin = hitPin(e.localPosition);
      if (pin != null) {
        setState(() {
          wireStart ??= pin;
          wireDragging = true;
          wireMoved = false;
          wirePreview = e.localPosition;
        });
      }
    }
  }

  void scenePointerMove(PointerMoveEvent e) {
    if (busy || pointers.length != 1) return;
    if (tool == 'select') {
      updateDrag(
        DragUpdateDetails(
          localPosition: e.localPosition,
          globalPosition: e.position,
          delta: e.delta,
        ),
      );
    }
    if (tool == 'wire' && wireDragging) {
      setState(() {
        wireMoved = true;
        wirePreview = e.localPosition;
      });
    }
  }

  void connectPins(String from, String to) {
    if (from == to ||
        wiresOf(project).any(
          (w) =>
              (w['from'] == from && w['to'] == to) ||
              (w['from'] == to && w['to'] == from),
        )) {
      return;
    }
    if (wiresOf(project).length >= 512) {
      toast('Limit: 512 wires.');
      return;
    }
    mutate(() => wiresOf(project).add({'from': from, 'to': to}));
    HapticFeedback.selectionClick();
  }

  void scenePointerUp(PointerUpEvent e) {
    if (pointers.length == 1) {
      if (dragId != null) endDrag();
      if (wireDragging && wireMoved && wireStart != null) {
        final pin = hitPin(e.localPosition);
        if (pin != null) connectPins(wireStart!, pin);
        setState(() {
          wireStart = null;
          wirePreview = null;
        });
      }
    }
    pointers.remove(e.pointer);
    wireDragging = false;
  }

  void doubleTapPart() {
    final id = hitComponent(lastDoubleTap ?? Offset.zero);
    if (id == null) return;
    final part = componentsOf(project).firstWhere((c) => c['id'] == id);
    setState(() => selected = id);
    if (part['type'] == 'switch') {
      final wasRunning = result != null;
      mutate(() => part['value'] = (part['value'] as num) > .5 ? 0.0 : 1.0);
      HapticFeedback.selectionClick();
      if (wasRunning) run();
    } else {
      editSelected();
    }
  }

  Widget floatingPanel(Widget child, {EdgeInsets padding = EdgeInsets.zero}) =>
      Material(
        color: panel,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: .35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: edge),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
  Widget toolControl(String id, IconData icon, String label) => Expanded(
    child: Tooltip(
      message: id == 'select'
          ? 'Select and move'
          : id == 'wire'
          ? 'Connect terminals'
          : 'Pan canvas',
      child: InkWell(
        onTap: busy ? null : () => changeTool(id),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 50,
          decoration: BoxDecoration(
            color: tool == id
                ? accent.withValues(alpha: .1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: tool == id ? accent : muted),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: tool == id ? softWhite : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget canvasPanel() => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      if (previousCanvasSize != size) {
        previousCanvasSize = size;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) fitCanvas(size);
        });
      }
      final ink = lightCanvas ? const Color(0xff34423b) : softWhite;
      return Stack(
        key: const ValueKey('circuit-viewport'),
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: transform,
              constrained: false,
              minScale: .12,
              maxScale: 4,
              boundaryMargin: const EdgeInsets.all(1000),
              panEnabled: tool == 'pan',
              scaleEnabled: true,
              child: Listener(
                onPointerDown: scenePointerDown,
                onPointerMove: scenePointerMove,
                onPointerUp: scenePointerUp,
                onPointerCancel: (e) {
                  pointers.remove(e.pointer);
                  endDrag();
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: tapCanvas,
                  onDoubleTapDown: (d) => lastDoubleTap = d.localPosition,
                  onDoubleTap: doubleTapPart,
                  child: ValueListenableBuilder<Matrix4>(
                    valueListenable: transform,
                    builder: (context, matrix, _) => CustomPaint(
                      key: const ValueKey('schematic-paint'),
                      size: const Size(worldWidth, worldHeight),
                      painter: CircuitPainter(
                        project,
                        selected: selected,
                        selectedWire: selectedWire,
                        wireStart: wireStart,
                        wirePreview: wirePreview,
                        result: result,
                        viewScale: matrix.getMaxScaleOnAxis(),
                        lightCanvas: lightCanvas,
                      ),
                      foregroundPainter: result == null
                          ? null
                          : CurrentFlowPainter(
                              project,
                              result!,
                              clock: flowClock,
                              viewScale: matrix.getMaxScaleOnAxis(),
                              lightCanvas: lightCanvas,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 18,
            left: 16,
            right: 72,
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WORKSPACE / 01',
                    style: technical(
                      size: 9,
                      color: lightCanvas ? const Color(0xff73827c) : muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: result != null ? accent : muted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          busy
                              ? 'Calculating…'
                              : result != null
                              ? (transient != null
                                    ? 'Transient · final sample'
                                    : 'DC operating point')
                              : 'Ready to simulate',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${componentsOf(project).length} parts  /  ${wiresOf(project).length} connections',
                    style: technical(
                      size: 9,
                      color: lightCanvas ? const Color(0xff73827c) : muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 12,
            child: SizedBox(
              width: 42,
              child: floatingPanel(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => zoomCanvas(1.3),
                      tooltip: 'Zoom in',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add, size: 18),
                    ),
                    ValueListenableBuilder<Matrix4>(
                      valueListenable: transform,
                      builder: (context, v, _) => Text(
                        '${(v.getMaxScaleOnAxis() * 100).round()}%',
                        style: technical(size: 8),
                      ),
                    ),
                    IconButton(
                      onPressed: () => zoomCanvas(1 / 1.3),
                      tooltip: 'Zoom out',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove, size: 18),
                    ),
                    const Divider(height: 1, indent: 10, endIndent: 10),
                    IconButton(
                      onPressed: () {
                        previousCanvasSize = null;
                        setState(() {});
                      },
                      tooltip: 'Fit circuit',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.center_focus_strong, size: 17),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (componentsOf(project).isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.polyline_outlined, size: 40, color: muted),
                    const SizedBox(height: 18),
                    Text(
                      'Start with a component',
                      style: TextStyle(
                        fontSize: 20,
                        color: ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add parts below, then connect their terminals.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          if (selectedComponent != null || selectedWire != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: result != null ? 140 : 92,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: floatingPanel(
                    Row(
                      children: [
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                selectedComponent?['label'] as String? ??
                                    'Wire',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (selectedComponent != null)
                                Text(
                                  componentValue(selectedComponent!),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: technical(size: 10),
                                ),
                            ],
                          ),
                        ),
                        if (selectedComponent != null) ...[
                          TextButton(
                            key: const ValueKey('edit-selection'),
                            onPressed: editSelected,
                            child: const Text('Edit'),
                          ),
                          IconButton(
                            onPressed: rotate,
                            tooltip: 'Rotate part',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.rotate_right, size: 18),
                          ),
                          IconButton(
                            onPressed: duplicate,
                            tooltip: 'Duplicate part',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.copy_outlined, size: 17),
                          ),
                        ],
                        IconButton(
                          onPressed: remove,
                          tooltip: 'Delete selection',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Color(0xffdf9c92),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (result != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 88,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: floatingPanel(
                    SizedBox(
                      height: 40,
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: currentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          const Expanded(
                            child: Text(
                              'CURRENT FLOW',
                              style: TextStyle(
                                fontFamily: 'SCMono',
                                fontSize: 9,
                                color: softWhite,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('toggle-current-flow'),
                            onPressed: toggleCurrentFlow,
                            tooltip: flowPlaying
                                ? 'Pause current flow'
                                : 'Play current flow',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              flowPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 19,
                              color: currentColor,
                            ),
                          ),
                          Container(height: 18, width: 1, color: edge),
                          PopupMenuButton<double>(
                            key: const ValueKey('flow-speed'),
                            tooltip: 'Playback speed',
                            onSelected: setFlowSpeed,
                            color: panel,
                            itemBuilder: (_) => [
                              for (final speed in [.5, 1.0, 2.0])
                                PopupMenuItem(
                                  value: speed,
                                  child: Text(
                                    '${speed == .5 ? '0.5' : speed.toInt()}×',
                                    style: technical(
                                      size: 12,
                                      color: softWhite,
                                    ),
                                  ),
                                ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Text(
                                '${flowSpeed == .5 ? '0.5' : flowSpeed.toInt()}×',
                                style: technical(size: 11, color: accent),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 14,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: floatingPanel(
                  Row(
                    children: [
                      IconButton(
                        key: const ValueKey('add-part'),
                        onPressed: busy ? null : chooseComponent,
                        tooltip: 'Add component',
                        icon: const Icon(
                          Icons.add_box_outlined,
                          size: 24,
                          color: accent,
                        ),
                      ),
                      Container(height: 28, width: 1, color: edge),
                      const SizedBox(width: 5),
                      toolControl('select', Icons.near_me_outlined, 'Select'),
                      toolControl('wire', Icons.cable, 'Wire'),
                      toolControl('pan', Icons.pan_tool_outlined, 'Pan'),
                      const SizedBox(width: 6),
                      FilledButton(
                        key: const ValueKey('run-simulation'),
                        onPressed: busy ? null : run,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 46),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              busy
                                  ? Icons.hourglass_empty
                                  : Icons.play_arrow_rounded,
                              size: 19,
                            ),
                            const SizedBox(width: 3),
                            const Text('Run', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(6),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  Future<void> copyCsv() async {
    if (result == null) {
      toast('Run a simulation first.');
      return;
    }
    String cell(Object? value) {
      var s = '$value';
      if (value is String && RegExp(r'^[=+\-@\t\r]').hasMatch(s)) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    final rows = <List<Object?>>[];
    if (transient != null) {
      rows.add([
        'Time (s)',
        'Component',
        'Voltage (V)',
        'Current (A)',
        'Power (W)',
      ]);
      for (final frame in transient!['samples'] as List) {
        for (final c in frame['components'] as List) {
          rows.add([
            frame['time'],
            c['label'],
            c['voltage'],
            c['current'],
            c['power'],
          ]);
        }
      }
    } else {
      rows.add(['Component', 'Voltage (V)', 'Current (A)', 'Power (W)']);
      for (final c in result!['components'] as List) {
        rows.add([c['label'], c['voltage'], c['current'], c['power']]);
      }
    }
    await Clipboard.setData(
      ClipboardData(text: rows.map((r) => r.map(cell).join(',')).join('\r\n')),
    );
    toast('CSV results copied.');
  }

  Future<void> chooseComponent() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: surfaceDeep,
      builder: (_) => const ComponentLibrary(),
    );
    if (type != null && mounted) {
      add(type);
      HapticFeedback.selectionClick();
    }
  }

  Future<void> editSelected() async {
    final c = selectedComponent;
    if (c == null) return;
    final id = c['id'];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: surfaceDeep,
      builder: (_) => ComponentEditor(
        component: Map<String, dynamic>.from(c),
        onApply: (data) {
          final current = componentsOf(project).where((p) => p['id'] == id);
          if (current.isNotEmpty) mutate(() => current.first.addAll(data));
        },
      ),
    );
  }

  Future<void> refreshShelf() async {
    if (!ready) return;
    setState(() {
      shelfLoading = true;
      shelfError = '';
    });
    try {
      final response = await request({'op': 'list'});
      if (mounted) {
        setState(
          () => savedProjects = (response['projects'] as List)
              .cast<Map<String, dynamic>>(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => shelfError = 'Could not load projects: $e');
    } finally {
      if (mounted) setState(() => shelfLoading = false);
    }
  }

  Future<void> openSaved(String id) async {
    if (busy) return;
    try {
      final data =
          (await request({'op': 'load', 'id': id}))['project']
              as Map<String, dynamic>;
      if (!mounted) return;
      mutate(() {
        project = data;
        previousCanvasSize = null;
        selected = null;
        selectedWire = null;
        wireStart = null;
        screen = 0;
      });
      setState(() => dirty = false);
      await checkpoint();
    } catch (e) {
      toast('Could not open circuit: $e');
    }
  }

  void navigate(int value) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => screen = value);
    syncFlowAnimation();
    if (value == 2) refreshShelf();
  }

  Widget mobileBuild() => canvasPanel();
  Widget mobileResults() {
    final nodes = List<dynamic>.from(result?['nets'] as List? ?? []);
    final plotted = List<dynamic>.from(nodes)
      ..sort(
        (a, b) =>
            (b['voltage'] as num).abs().compareTo((a['voltage'] as num).abs()),
      );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      children: [
        const Text(
          'Circuit analysis',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'DC operating points and time-domain responses.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 22),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'simulate',
              label: Text('DC', style: TextStyle(fontSize: 12)),
              icon: Icon(Icons.bolt, size: 16),
            ),
            ButtonSegment(
              value: 'transient',
              label: Text('Transient', style: TextStyle(fontSize: 12)),
              icon: Icon(Icons.show_chart, size: 16),
            ),
          ],
          selected: {analysis},
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: busy
              ? null
              : (v) => setState(() {
                  analysis = v.first;
                  result = null;
                  transient = null;
                  error = '';
                  flowClock.stop();
                }),
        ),
        if (analysis == 'transient')
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: TextField(
              controller: duration,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Duration · milliseconds',
                helperText: 'Zero initial energy. Sources turn on at t = 0.',
                helperMaxLines: 2,
              ),
            ),
          ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(34),
            child: Center(child: CircularProgressIndicator(color: accent)),
          ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: LabSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Color(0xfff1c67a),
                        size: 20,
                      ),
                      SizedBox(width: 9),
                      Text(
                        'Check your circuit',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  TextButton(
                    onPressed: () => navigate(0),
                    child: const Text('Back to build'),
                  ),
                ],
              ),
            ),
          ),
        if (!busy && result == null && error.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: LabSurface(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.multiline_chart_rounded, size: 36, color: accent),
                  SizedBox(height: 20),
                  Text(
                    'Ready when you are.',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Run a simulation to reveal voltages, currents and power in every branch.',
                    style: TextStyle(fontSize: 12, color: muted, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        if (result != null) ...[
          const SizedBox(height: 22),
          LabSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'POWER DISSIPATED',
                        style: TextStyle(
                          fontFamily: 'SCMono',
                          color: muted,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    Text(
                      analysis == 'transient' ? 'FINAL SAMPLE' : 'DC RESULT',
                      style: technical(size: 8, color: accent),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  engineering(result!['dissipatedPower'] as num, 'W'),
                  style: const TextStyle(
                    fontSize: 34,
                    color: accent,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${(result!['components'] as List).length} component readings',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => navigate(0),
                      icon: const Icon(Icons.arrow_outward, size: 14),
                      label: const Text(
                        'View flow',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (transient != null)
            LabSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LabSection('Transient response'),
                  const SizedBox(height: 12),
                  DropdownButton<String>(
                    value: observedCapacitor,
                    isExpanded: true,
                    underline: Container(height: 1, color: edge),
                    items: [
                      for (final c in componentsOf(
                        project,
                      ).where((c) => c['type'] != 'ground'))
                        DropdownMenuItem(
                          value: c['id'] as String,
                          child: Text(
                            '${c['label']}  ·  ${componentNames[c['type']]}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => chartComponent = v),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    children: [
                      for (final metric in const [
                        'voltage',
                        'current',
                        'power',
                      ])
                        ChoiceChip(
                          label: Text(
                            metric[0].toUpperCase() + metric.substring(1),
                            style: const TextStyle(fontSize: 10),
                          ),
                          selected: chartMetric == metric,
                          onSelected: (_) =>
                              setState(() => chartMetric = metric),
                          showCheckmark: false,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: ResultChart(
                        (transient!['samples'] as List)
                            .cast<Map<String, dynamic>>(),
                        observedCapacitor,
                        metric: chartMetric,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '0 → ${engineering(transient!['duration'] as num, 's')}  /  200 steps',
                    style: technical(size: 9),
                  ),
                ],
              ),
            )
          else if (nodes.isNotEmpty)
            LabSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LabSection('Node voltages'),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: math.min(nodes.length, 6) * 32.0,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: NodeVoltagePlot(plotted.take(6).toList()),
                    ),
                  ),
                  if (nodes.length > 6)
                    Text(
                      'Six largest potentials · full list below',
                      style: technical(size: 8),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          LabSection(
            'Component readings',
            trailing: TextButton(
              onPressed: copyCsv,
              child: const Text('Copy CSV', style: TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(height: 10),
          for (final row in result!['components'] as List)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LabSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row['label'] as String,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          (componentNames[row['type']] ?? 'Component')
                              .toUpperCase(),
                          style: technical(size: 8, color: accent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, c) => Wrap(
                        spacing: 12,
                        runSpacing: 16,
                        children: [
                          for (final item in {
                            'Voltage': engineering(row['voltage'] as num, 'V'),
                            'Current': engineering(row['current'] as num, 'A'),
                            'Power': engineering(row['power'] as num, 'W'),
                          }.entries)
                            SizedBox(
                              width: math.max(82, (c.maxWidth - 24) / 3),
                              child: LabMetric(item.key, item.value),
                            ),
                        ],
                      ),
                    ),
                    if (row['state'] is String ||
                        row['baseCurrent'] is num ||
                        row['wiperVoltage'] is num) ...[
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          if (row['state'] is String)
                            Text(
                              row['state'] as String,
                              style: technical(size: 10, color: accent),
                            ),
                          if (row['baseCurrent'] is num)
                            Text(
                              'IB ${engineering(row['baseCurrent'] as num, 'A')}',
                              style: technical(size: 10),
                            ),
                          if (row['vbe'] is num)
                            Text(
                              'VBE ${engineering(row['vbe'] as num, 'V')}',
                              style: technical(size: 10),
                            ),
                          if (row['wiperVoltage'] is num)
                            Text(
                              'Wiper ${engineering(row['wiperVoltage'] as num, 'V')}',
                              style: technical(size: 10),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            'Positive current follows the first pin to the second. For BJTs, readings are VCE and IC.',
            style: TextStyle(color: muted, fontSize: 10, height: 1.6),
          ),
          const SizedBox(height: 24),
          const LabSection('All node potentials'),
          const SizedBox(height: 12),
          for (final row in nodes)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(row['name'] as String, style: technical(size: 11)),
              trailing: Text(
                engineering(row['voltage'] as num, 'V'),
                style: technical(size: 12, color: softWhite),
              ),
            ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('GND', style: technical(size: 11)),
            trailing: Text('0 V', style: technical(size: 12, color: softWhite)),
          ),
        ],
      ],
    );
  }

  Widget mobileProjects() => RefreshIndicator(
    onRefresh: refreshShelf,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your circuits.',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.3,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: busy ? null : newProject,
              icon: const Icon(Icons.add, size: 17),
              label: const Text('New', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 9),
        const Text(
          'Saved projects and ready-to-run examples.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 26),
        LabSection(
          'Saved projects',
          trailing: Text('${savedProjects.length}', style: technical(size: 10)),
        ),
        const SizedBox(height: 14),
        if (shelfLoading) const LinearProgressIndicator(color: accent),
        if (shelfError.isNotEmpty)
          Text(shelfError, style: const TextStyle(color: accent)),
        if (!shelfLoading && savedProjects.isEmpty && shelfError.isEmpty)
          const LabSurface(
            child: Row(
              children: [
                Icon(Icons.folder_open_outlined, size: 28, color: muted),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Your saved circuits will appear here.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              ],
            ),
          ),
        for (final p in savedProjects)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LabSurface(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.description_outlined, color: accent),
                title: Text(
                  p['title'] as String,
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: muted,
                ),
                onTap: busy ? null : () => openSaved(p['id'] as String),
              ),
            ),
          ),
        const SizedBox(height: 28),
        const LabSection('Start with a circuit'),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final e in exampleCatalog.entries)
                SizedBox(
                  width:
                      (c.maxWidth - (c.maxWidth > 700 ? 24 : 12)) /
                      (c.maxWidth > 700 ? 3 : 2),
                  child: Material(
                    color: panel,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: const BorderSide(color: edge),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('example-${e.key}'),
                      onTap: busy
                          ? null
                          : () async {
                              await loadExample(e.key);
                              if (mounted) navigate(0);
                            },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 100,
                            decoration: const BoxDecoration(
                              color: Color(0xff101b1e),
                              border: Border(bottom: BorderSide(color: edge)),
                            ),
                            child: CircuitPreview(e.key),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.value[0],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        ['rc', 'rl'].contains(e.key)
                                            ? 'TRANSIENT'
                                            : 'DC STUDY',
                                        style: technical(size: 8),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.north_east,
                                      size: 13,
                                      color: accent,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : importProject,
              icon: const Icon(Icons.input, size: 16),
              label: const Text('Import JSON', style: TextStyle(fontSize: 11)),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : exportProject,
              icon: const Icon(Icons.ios_share, size: 16),
              label: const Text('Export JSON', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    ),
  );
  Widget navigationTab(int i) {
    const keys = ['build', 'results', 'projects'];
    const labels = ['Build', 'Results', 'Projects'];
    const icons = [
      Icons.polyline_outlined,
      Icons.show_chart_rounded,
      Icons.grid_view_rounded,
    ];
    return Semantics(
      selected: screen == i,
      button: true,
      child: InkWell(
        key: ValueKey('nav-${keys[i]}'),
        onTap: ready ? () => navigate(i) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 38,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: screen == i ? accent : edge,
                width: screen == i ? 2 : 1,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icons[i], size: 14, color: screen == i ? accent : muted),
              const SizedBox(width: 7),
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: screen == i ? FontWeight.w600 : FontWeight.w400,
                  color: screen == i ? softWhite : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 52,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      leadingWidth: 56,
      leading: const Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: LabLogo(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            screen == 0
                ? project['title'] as String
                : screen == 1
                ? 'Analysis'
                : 'Circuit library',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            screen == 0
                ? (dirty ? 'Draft · recovery enabled' : 'SHORT CIRCUIT')
                : 'SHORT CIRCUIT',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: technical(size: 8),
          ),
        ],
      ),
      actions: [
        if (screen == 0)
          IconButton(
            onPressed: undo.isEmpty || busy ? null : () => history(true),
            tooltip: 'Undo',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.undo_rounded, size: 19),
          ),
        IconButton(
          onPressed: ready && !busy ? save : null,
          tooltip: 'Save project',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.save_outlined, size: 20),
        ),
        PopupMenuButton<String>(
          enabled: ready && !busy,
          icon: const Icon(Icons.more_horiz, size: 22),
          onSelected: (v) {
            switch (v) {
              case 'examples':
                examples();
              case 'new':
                newProject();
              case 'export':
                exportProject();
              case 'import':
                importProject();
              case 'guide':
                showGuide();
              case 'canvas':
                setState(() => lightCanvas = !lightCanvas);
              case 'redo':
                history(false);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'new', child: Text('New circuit')),
            const PopupMenuItem(
              value: 'examples',
              child: Text('Starter examples'),
            ),
            PopupMenuItem(
              value: 'redo',
              enabled: redo.isNotEmpty,
              child: const Text('Redo'),
            ),
            const PopupMenuItem(value: 'import', child: Text('Import project')),
            const PopupMenuItem(value: 'export', child: Text('Export project')),
            PopupMenuItem(
              value: 'canvas',
              child: Text(lightCanvas ? 'Use dark canvas' : 'Use light canvas'),
            ),
            const PopupMenuItem(value: 'guide', child: Text('Quick guide')),
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(38),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (int i = 0; i < 3; i++) Expanded(child: navigationTab(i)),
            ],
          ),
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      child: !ready
          ? const Center(child: CircularProgressIndicator(color: accent))
          : switch (screen) {
              0 => mobileBuild(),
              1 => Column(
                children: [
                  Expanded(child: mobileResults()),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('run-simulation'),
                        onPressed: busy ? null : run,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            busy
                                ? 'Calculating…'
                                : analysis == 'transient'
                                ? 'Run transient'
                                : 'Run simulation',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              _ => mobileProjects(),
            },
    ),
  );
}

// Keep the controller alive until the dialog route has finished dismissing.
class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog({
    required this.title,
    required this.label,
    required this.action,
    this.initialText = '',
    this.maxLength,
    this.maxLines = 1,
  });
  final String title, label, action, initialText;
  final int? maxLength;
  final int maxLines;
  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  late final controller = TextEditingController(text: widget.initialText);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 500,
      child: TextField(
        controller: controller,
        maxLength: widget.maxLength,
        maxLines: widget.maxLines,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text.trim()),
        child: Text(widget.action),
      ),
    ],
  );
}
