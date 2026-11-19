import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:short_circuit/component_library.dart';
import 'package:short_circuit/current_flow.dart';
import 'package:short_circuit_core/short_circuit_core.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:short_circuit/main.dart';
import 'package:short_circuit/project_view.dart';

// This double checks UI contracts only. Native numbers are tested separately.
class FakeBackend {
  final requests = <Map<String, dynamic>>[];
  final saved = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? recovered;
  Future<Map<String, dynamic>> call(Map<String, dynamic> request) async {
    requests.add(jsonDecode(jsonEncode(request)) as Map<String, dynamic>);
    switch (request['op']) {
      case 'restore':
        return {'ok': true, 'project': recovered, 'dirty': recovered != null};
      case 'checkpoint':
        return {'ok': true};
      case 'save':
        final p = copyProject(request['project'] as Map<String, dynamic>);
        saved[p['id'] as String] = p;
        return {'ok': true};
      case 'list':
        return {
          'ok': true,
          'projects': saved.values
              .map((p) => {'id': p['id'], 'title': p['title']})
              .toList(),
        };
      case 'load':
        return {'ok': true, 'project': copyProject(saved[request['id']]!)};
      case 'simulate':
        return {
          'ok': true,
          'result': {
            'dissipatedPower': .048,
            'powerBalance': 0,
            'components': [
              {
                'id': 'R2',
                'label': 'R2',
                'voltage': 8,
                'current': .004,
                'power': .032,
              },
            ],
            'nets': [
              {'name': 'N1', 'voltage': 12},
              {'name': 'N2', 'voltage': 8},
            ],
          },
        };
      default:
        throw StateError('Unexpected UI request ${request['op']}');
    }
  }
}

class FlowBackend extends FakeBackend {
  @override
  Future<Map<String, dynamic>> call(Map<String, dynamic> request) async {
    if (request['op'] == 'simulate' || request['op'] == 'transient') {
      requests.add(copyProject(request));
      return executeNative(request);
    }
    return super.call(request);
  }
}

Future<void> mount(
  WidgetTester tester,
  FakeBackend backend,
  Size size, {
  double scale = 1,
  bool animations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('qa-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shortCircuitTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: !animations,
          ),
          child: child!,
        ),
        home: Workbench(
          nativeRequest: backend.call,
          projectDirectory: '/fake-mobile-projects',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump();
}

Future<void> capture(WidgetTester tester, String name) async {
  void repaint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(repaint);
  }

  debugDisableShadows = false;
  repaint(tester.binding.renderViews.first);
  await tester.pump();
  try {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('qa-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory('build/test-output')
        ..createSync(recursive: true);
      File(
        '${folder.path}/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  } finally {
    debugDisableShadows = true;
    repaint(tester.binding.renderViews.first);
    await tester.pump();
  }
}

Future<void> addPart(WidgetTester tester, String type, String query) async {
  await tester.tap(find.byTooltip('Add component'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('component-search')), query);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('part-$type')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    for (final entry in {
      'SpaceGrotesk': 'assets/fonts/SpaceGrotesk.ttf',
      'SCMono': 'assets/fonts/JetBrainsMono-Regular.ttf',
    }.entries) {
      final font = File(entry.value);
      await (FontLoader(entry.key)..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
    }
    final mono = File('C:/Windows/Fonts/consola.ttf');
    if (mono.existsSync()) {
      await (FontLoader('monospace')..addFont(
            Future.value(ByteData.sublistView(mono.readAsBytesSync())),
          ))
          .load();
    }
    final regular = File('C:/Windows/Fonts/segoeui.ttf');
    if (regular.existsSync()) {
      final loader = FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(regular.readAsBytesSync())));
      await loader.load();
    }
    final icons = File(
      'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
  });
  setUp(() {
    // Keep asset futures on the fake test clock instead of waiting on real IO.
    rootBundle.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          final source = File(key);
          final file = source.existsSync()
              ? source
              : File('build/unit_test_assets/$key');
          return file.existsSync()
              ? ByteData.sublistView(file.readAsBytesSync())
              : null;
        });
  });

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(780, 390),
  ]) {
    testWidgets('Phone layout fits ${size.width} by ${size.height}', (
      tester,
    ) async {
      await mount(tester, FakeBackend(), size);
      final viewport = tester.getSize(
        find.byKey(const ValueKey('circuit-viewport')),
      );
      expect(viewport.height / size.height, greaterThan(.74));
      expect(viewport.width, size.width);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.constrained, isFalse);
      final schematic =
          tester
                  .widgetList<CustomPaint>(find.byType(CustomPaint))
                  .firstWhere((c) => c.painter is CircuitPainter)
                  .painter
              as CircuitPainter;
      expect(
        schematic.viewScale,
        closeTo(
          viewer.transformationController!.value.getMaxScaleOnAxis(),
          .001,
        ),
      );
      if (size.width < 500) {
        expect(
          viewer.transformationController!.value.getMaxScaleOnAxis(),
          lessThan(.8),
        );
      }
      expect(worldWidth, greaterThan(4000));
      await capture(
        tester,
        'workspace-${size.width.toInt()}x${size.height.toInt()}',
      );
      expect(find.byKey(const ValueKey('run-simulation')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('Large text fits a narrow phone', (tester) async {
    await mount(tester, FakeBackend(), const Size(320, 720), scale: 1.4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Explicit Apply changes SI value and recovery payload', (
    tester,
  ) async {
    final backend = FakeBackend();
    await mount(tester, backend, const Size(390, 844));
    await tester.tap(find.byTooltip('Add component'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('part-capacitor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-selection')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('component-value')),
      '22u',
    );
    await tester.tap(find.byKey(const ValueKey('apply-component')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    final checkpoint = backend.requests.lastWhere(
      (r) => r['op'] == 'checkpoint',
    );
    final capacitor = componentsOf(
      checkpoint['project'] as Map<String, dynamic>,
    ).firstWhere((c) => c['type'] == 'capacitor');
    expect(capacitor['value'], closeTo(22e-6, 1e-12));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Invalid resistance stays in the editor with an error', (
    tester,
  ) async {
    await mount(tester, FakeBackend(), const Size(390, 844));
    await tester.tap(find.byTooltip('Add component'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('part-resistor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-selection')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('component-value')), '0');
    await tester.tap(find.byKey(const ValueKey('apply-component')));
    await tester.pumpAndSettle();
    expect(find.text('Use 1 micro-ohm to 1 tera-ohm.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Run opens readable result cards', (tester) async {
    final backend = FakeBackend();
    await mount(tester, backend, const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('run-simulation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('circuit-viewport')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-results')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('COMPONENT READINGS'), 100);
    await tester.pumpAndSettle();
    expect(find.text('COMPONENT READINGS'), findsOneWidget);
    await capture(tester, 'analysis-dc');
    await tester.scrollUntilVisible(find.text(engineering(8, 'V')).first, 100);
    expect(find.text(engineering(8, 'V')), findsWidgets);
    expect(backend.requests.any((r) => r['op'] == 'simulate'), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Named save appears on the shelf and loads again', (
    tester,
  ) async {
    final backend = FakeBackend();
    await mount(tester, backend, const Size(390, 844));
    await tester.tap(find.byTooltip('Save project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Moiz mobile lab');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Moiz mobile lab'), 150);
    await tester.tap(find.text('Moiz mobile lab'));
    await tester.pumpAndSettle();
    expect(backend.requests.any((r) => r['op'] == 'load'), isTrue);
    expect(find.text('Moiz mobile lab'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('An unfinished workspace is recovered at startup', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..recovered = {
        'schema': 1,
        'id': 'unfinished',
        'title': 'Unfinished circuit',
        'components': [],
        'wires': [],
      };
    await mount(tester, backend, const Size(390, 844));
    expect(find.text('Unfinished circuit'), findsWidgets);
    expect(find.text('Draft · recovery enabled'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Search filters all 13 available component models', (
    tester,
  ) async {
    await mount(tester, FakeBackend(), const Size(390, 844));
    await tester.tap(find.byTooltip('Add component'));
    await tester.pumpAndSettle();
    expect(find.byType(ComponentLibrary), findsOneWidget);
    await capture(tester, 'component-library');
    for (final type in componentNames.keys) {
      await tester.enterText(
        find.byKey(const ValueKey('component-search')),
        componentNames[type]!,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('part-$type')), findsOneWidget);
    }
    await tester.enterText(
      find.byKey(const ValueKey('component-search')),
      'no-such-part',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching components'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Potentiometer editing retains the third terminal and wiper', (
    tester,
  ) async {
    final backend = FakeBackend();
    await mount(tester, backend, const Size(390, 844));
    await addPart(tester, 'potentiometer', 'potentiometer');
    await tester.tap(find.byKey(const ValueKey('edit-selection')));
    await tester.pumpAndSettle();
    await capture(tester, 'potentiometer-editor');
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(.25);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('apply-component')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    final p =
        backend.requests.lastWhere((r) => r['op'] == 'checkpoint')['project']
            as Map<String, dynamic>;
    final pot = componentsOf(p).firstWhere((c) => c['type'] == 'potentiometer');
    expect(pot['setting'], .25);
    expect(pinCount('potentiometer'), 3);
    expect(
      (pinPosition(pot, 2) - pinPosition(pot, 0)).distance,
      greaterThan(40),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Two-finger pinch zooms while Select is active', (tester) async {
    await mount(tester, FakeBackend(), const Size(390, 844));
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final before = controller.value.getMaxScaleOnAxis();
    final center = tester.getCenter(
      find.byKey(const ValueKey('circuit-viewport')),
    );
    final one = await tester.startGesture(
      center + const Offset(-30, 30),
      pointer: 1,
    );
    final two = await tester.startGesture(
      center + const Offset(30, 30),
      pointer: 2,
    );
    await tester.pump();
    await one.moveBy(const Offset(-50, 0));
    await two.moveBy(const Offset(50, 0));
    await tester.pump();
    await one.up();
    await two.up();
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(before * 1.4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Projects contains the new starter circuits', (tester) async {
    await mount(tester, FakeBackend(), const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('nav-projects')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await capture(tester, 'projects');
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.label ?? '').contains(
              'Voltage divider schematic preview',
            ),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('example-npn')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('example-npn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('example-npn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('circuit-viewport')), findsOneWidget);
    expect(find.text('NPN transistor'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Three-terminal parts wire the selected pin when zoomed out', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..recovered = {
        'schema': 1,
        'id': 'pin-test',
        'title': 'Third-pin wiring',
        'components': [
          {
            'id': 'RV1',
            'label': 'RV1',
            'type': 'potentiometer',
            'value': 10000,
            'setting': .5,
            'x': 120,
            'y': 400,
            'rotation': 0,
          },
          {
            'id': 'G1',
            'label': 'GND',
            'type': 'ground',
            'value': 0,
            'x': 520,
            'y': 400,
            'rotation': 0,
          },
        ],
        'wires': <dynamic>[],
      };
    await mount(tester, backend, const Size(390, 844));
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(30, 0, 0, 1)
      ..scaleByDouble(.25, .25, .25, 1);
    await tester.pump();
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('circuit-viewport')),
    );
    await tester.tapAt(origin + const Offset(60, 112));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tapAt(origin + const Offset(160, 100));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    final p =
        backend.requests.lastWhere((r) => r['op'] == 'checkpoint')['project']
            as Map<String, dynamic>;
    expect(wiresOf(p).single, {'from': 'RV1:2', 'to': 'G1:0'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Native current markers move, pause, and stop away from the editor',
    (tester) async {
      final backend = FlowBackend();
      await mount(tester, backend, const Size(390, 844), animations: true);
      await tester.tap(find.byKey(const ValueKey('run-simulation')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      CurrentFlowPainter flow() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('schematic-paint')),
                  )
                  .foregroundPainter!
              as CurrentFlowPainter;
      expect(flow().result['wires'], isNotEmpty);
      final clock = flow().clock as AnimationController;
      expect(clock.isAnimating, isTrue);
      await capture(tester, 'flow-frame-a');
      final first = clock.value;
      await tester.pump(const Duration(milliseconds: 300));
      expect(clock.value, greaterThan(first));
      await capture(tester, 'flow-frame-b');
      expect(
        File('build/test-output/flow-frame-a.png').readAsBytesSync(),
        isNot(
          orderedEquals(
            File('build/test-output/flow-frame-b.png').readAsBytesSync(),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('toggle-current-flow')));
      await tester.pump();
      final paused = clock.value;
      await tester.pump(const Duration(seconds: 1));
      expect(clock.value, paused);
      expect(clock.isAnimating, isFalse);
      await tester.pumpAndSettle();
      clock.value = 0;
      await tester.pump();
      await capture(tester, 'flow-loop-start');
      clock.value = 1;
      await tester.pump();
      await capture(tester, 'flow-loop-end');
      expect(
        File('build/test-output/flow-loop-start.png').readAsBytesSync(),
        orderedEquals(
          File('build/test-output/flow-loop-end.png').readAsBytesSync(),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('toggle-current-flow')));
      await tester.pump();
      expect(clock.isAnimating, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(clock.isAnimating, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(clock.isAnimating, isTrue);
      await tester.tap(find.byKey(const ValueKey('nav-results')));
      await tester.pumpAndSettle();
      expect(clock.isAnimating, isFalse);
      expect(backend.requests.where((r) => r['op'] == 'simulate').length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Reduced motion keeps current arrows still', (tester) async {
    await mount(tester, FlowBackend(), const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('run-simulation')));
    await tester.pumpAndSettle();
    final flow =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('schematic-paint')),
                )
                .foregroundPainter!
            as CurrentFlowPainter;
    expect((flow.clock as AnimationController).isAnimating, isFalse);
    expect(flow.result['wires'], isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('An open switch does not start a current animation', (
    tester,
  ) async {
    final backend = FlowBackend()
      ..recovered =
          jsonDecode(File('examples/switch.sc.json').readAsStringSync())
              as Map<String, dynamic>;
    await mount(tester, backend, const Size(390, 844), animations: true);
    await tester.tap(find.byKey(const ValueKey('run-simulation')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final flow =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('schematic-paint')),
                )
                .foregroundPainter!
            as CurrentFlowPainter;
    expect((flow.clock as AnimationController).isAnimating, isFalse);
    expect(
      (flow.result['wires'] as List).every(
        (w) => !CurrentFlowPainter.carriesCurrent(w['current']),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Playback speed changes timing without overriding reduced motion',
    (tester) async {
      await mount(tester, FlowBackend(), const Size(390, 844));
      await tester.tap(find.byKey(const ValueKey('run-simulation')));
      await tester.pumpAndSettle();
      final flow =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('schematic-paint')),
                  )
                  .foregroundPainter!
              as CurrentFlowPainter;
      final clock = flow.clock as AnimationController;
      await tester.tap(find.byKey(const ValueKey('flow-speed')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2×').last);
      await tester.pumpAndSettle();
      expect(clock.duration, const Duration(seconds: 5));
      expect(clock.isAnimating, isFalse);
      await tester.tap(find.byKey(const ValueKey('flow-speed')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0.5×').last);
      await tester.pumpAndSettle();
      expect(clock.duration, const Duration(seconds: 20));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('RC analysis keeps its voltage and current waveform visible', (
    tester,
  ) async {
    final backend = FlowBackend()
      ..recovered =
          jsonDecode(File('examples/rc.sc.json').readAsStringSync())
              as Map<String, dynamic>;
    await mount(tester, backend, const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('nav-results')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transient'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('run-simulation')));
    await tester.pumpAndSettle();
    final chart = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is ResultChart,
    );
    await tester.scrollUntilVisible(
      chart,
      140,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    ResultChart plot() =>
        tester.widget<CustomPaint>(chart).painter! as ResultChart;
    expect(plot().samples.length, 201);
    expect(plot().component, 'C1');
    expect(plot().metric, 'voltage');
    final last = plot().samples.last['components'] as List;
    expect(
      last.firstWhere((c) => c['id'] == 'C1')['voltage'],
      greaterThan(4.9),
    );
    await capture(tester, 'analysis-transient');
    await tester.ensureVisible(find.text('Current').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Current').last);
    await tester.pumpAndSettle();
    expect(plot().metric, 'current');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
