# Short Circuit architecture
The production app is a Flutter interface backed by one C++17 library. Dart keeps editable view data such as position and rotation; C++ constructs and owns the electrical model on each request.

| Layer | Responsibility | Source |
| --- | --- | --- |
| Flutter | Screens, touch interactions, component property forms, view history, platform application-directory lookup | lib/ |
| Native bridge | JSON requests, UTF-8 allocation, C ABI calls, freeing every returned buffer | packages/short_circuit_core/lib/ |
| C++ model | Abstract Component and concrete Resistor, VoltageSource, CurrentSource, Capacitor, Inductor, Switch, Potentiometer, Diode (diode/LED/Zener), Bjt (NPN/PNP), Ground | packages/short_circuit_core/src/engine.hpp |
| Circuit | Owns components through unique_ptr, owns Node and Wire objects, merges wired terminals and ground references | Circuit |
| SimulationEngine | Modified nodal analysis; row-scaled Gaussian elimination with partial pivoting; backward-Euler RC/RL/RLC integration and damped Newton iteration | SimulationEngine |
| ProjectManager | JSON project and index reading/writing using fstream; safe project identifiers; exceptions for invalid paths and failed reads/writes | ProjectManager |
| Development preview | Dependency-free HTML/CSS/JS editor with a reference solver; optional Python host calls the compiled C++ library | preview/, tools/serve.py |

## OOP requirements
Component is abstract: type(), validate(), stamp(), and current() are pure virtual. The engine calls stamp() through base pointers to perform runtime polymorphism. Concrete components override these operations. Private data members have getters and validated setters. Constructors establish initial state; virtual destructors and unique_ptr release each component. Circuit owns its Component, Node, and Wire objects by composition.

ProjectManager uses fstream in C++. All errors cross the C ABI as {"ok":false,"error":"..."}; C++ exceptions do not cross into Dart. Each successful or unsuccessful native response is freed with sc_free. Flutter runs requests in worker isolates and serializes operations.

## Numerical conventions
Terminal 1 is positive/reference-current entry; terminal 2 is negative/reference-current exit. Voltage means V(terminal 1) − V(terminal 2). Positive current flows from terminal 1 to terminal 2. Power is V × I, so negative source power indicates delivered power.

All grounds are one net. A wire joins terminal IDs directly. Visual crossings never create a connection. Multiple wires can share a terminal to form a junction.

DC treats capacitors as open circuits. Transient analysis constrains each capacitor to 0 V in the initial sample and applies constant sources at t = 0. Later samples use g = C/Δt with a history current. This models an RC step response, without arbitrary waveforms. Initial conditions must be consistent; an ideal source directly across an initially uncharged ideal capacitor produces conflicting constraints.

Topology and singular-matrix checks reject missing ground, dangling terminal references, shorted voltage sources, floating networks, conflicting sources and redundant ideal-source loops. Resource limits: 128 components, 512 wires, 2 MB project JSON, 1000 transient steps.

## Build and runtime
The native build hook compiles the library as C++17 and bundles it with Flutter. The production app has no Dart or JavaScript circuit solver. The browser preview uses a separate JavaScript reference adapter only when no native library is connected; its footer identifies that mode. With tools/serve.py and a compiled shared library, the same browser UI uses C++ for simulation and saving.

The browser preview's localStorage projects and the Flutter app's C++ files are separate stores. Export/import JSON transfers circuits between them.

## Sources used for integration
- https://docs.flutter.dev/platform-integration/bind-native-code
- https://pub.dev/documentation/native_toolchain_c/latest/native_toolchain_c/CBuilder/CBuilder.library.html
- https://pub.dev/documentation/hooks/latest/hooks/build.html
- https://pub.dev/packages/code_assets
- https://pub.dev/packages/path_provider


## Native mobile UI and recovery

The phone interface has Build, Results, and Projects destinations. Build allocates remaining screen height to the canvas and switches to a compact layout in landscape. Property edits use a validated bottom sheet with an explicit Apply action. The canvas fills the remaining screen. Floating tool docks leave it visible, while the component library and editor open as sheets. Pinch zoom remains active in Select, Wire and Pan. The world is 4800 × 3200 logical units.

Edits schedule a C++ workspace checkpoint after 650 ms. Lifecycle changes request a checkpoint when the app leaves the foreground. ProjectManager stores workspace.json separately from the named-project index, and restore loads that draft at startup. Requests are serialized; named saves only clear the dirty flag if no subsequent edit occurred. Recovery uses ordinary fstream writes and is best effort rather than journaled.

Android requires the C++ shared runtime alongside the engine library. The package depends on android_libcpp_shared to bundle it. A host-generation script derives the Gradle wrapper and configuration from the installed Flutter SDK and preserves checked-in manifest, launcher, themes, and app source. The CI workflow includes actual Android emulator startup and native simulation coverage, but it has not run in this environment.

## Extended models in 0.3

Inductors introduce an MNA branch unknown; DC imposes zero voltage, the initial transient sample imposes zero current, and later samples use V − (L/Δt)I = −(L/Δt)Iprevious. History is keyed by component ID so capacitor initial constraints cannot shift branch histories.

Nonlinear devices stamp Jacobian conductances and equivalent currents. Newton steps limit junction-voltage movement, with separate voltage/current convergence tolerances and a 250-iteration limit. Diode/LED reference voltage is calibrated at 1 mA. Zener reverse slope is 10 Ω. BJTs use an analytic three-terminal Ebers–Moll Jacobian, with emitter/base/collector KCL and total three-terminal power. Potentiometer power includes both resistive segments.

Terminal indices are zero based in JSON: two-terminal parts use :0 and :1; potentiometers use A:0, B:1, W:2; transistors use C:0, E:1, B:2. For BJTs, generic voltage/current readings mean VCE/IC, with base current and VBE supplied separately.

## Native current tracing and animation (0.4)

Component::terminalCurrents() returns signed currents entering each terminal. Potentiometer and BipolarTransistor override the two-terminal default. SimulationEngine emits these currents and a per-wire result. A Tarjan bridge traversal of the terminal/wire graph, including virtual ground-reference links, sums subtree current injections to determine each bridge current. Parallel or cyclic ideal-wire paths are marked indeterminate with a null current.

CurrentFlowPainter animates a separate foreground layer through signed native wire and component currents. It repaints from one AnimationController; it does not rerun the solver every frame or rebuild the widget tree. Direction is conventional current, speed is a visual logarithmic magnitude cue, and currents below 1 nA do not animate. Lifecycle, editor navigation, pause, reduced motion and invalidated results stop the ticker.

## Connected particle rendering (0.5)

CurrentFlowGeometry turns native signed currents into directed display edges. Two-terminal components and native three-terminal currents contribute symbol paths. Adjacent edges are joined only when the intervening terminal has one incoming edge, one outgoing edge and equal current magnitude. Junctions retain separate streams; closed series loops become a single continuous route. This grouping is rendering logic and does not solve the electrical circuit.

Each route caches its PathMetric. The foreground painter draws small particle cores, halos and segmented fading trails, culling particles outside the viewport. Integer repeat cycles preserve the loop boundary. Speed selection changes the AnimationController duration while preserving the current phase. Wires and particles share corner geometry.

The design system supplies a custom vector circuit monogram, shared surfaces, real schematic thumbnails and node-voltage plots. Space Grotesk and JetBrains Mono are bundled offline, with their OFL license files.
