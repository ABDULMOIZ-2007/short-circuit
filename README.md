# Short Circuit 0.5 — Android mobile app

Flutter provides the mobile interface; C++17 owns the electrical model, numerical solver and project persistence.

## Install or run

Install releases/Short_Circuit_Android.apk on an Android ARM64 phone (Android 7 or later). This update retains the application ID and development signing key from versions 0.2, 0.3 and 0.4, so it can be installed over that version. Save important circuits before updating.

For source builds, see MOBILE_BUILD.md. The tested tools are Flutter 3.47.8, Dart 3.13.7, Java 21, Android SDK 36 and NDK 28.2.13676358. RUN_ANDROID.cmd runs the app on a connected device; BUILD_ANDROID.cmd builds a debug APK. The application ID is edu.moiz.short_circuit.

## CSC241 Level 2

The [Level 2 C++17 demonstration](level2/README.md) is a compact console implementation of the same 12 V divider shipped with the app. It includes the class diagram, build commands, and a guide to the OOP relationships. Use MOBILE_BUILD.md to build the Flutter application with the full native engine.

The [Level 2 design document](docs/Short_Circuit_Level_2_Design.pdf) covers the UML, build setup, and verified divider demonstration.

## Mobile workspace

- Full-screen 4800 × 3200 schematic canvas, with a light or dark background.
- A dark instrument-style workspace with a custom circuit monogram, Space Grotesk / JetBrains Mono typography, lime controls, floating tools and compact zoom/fit controls. Two-finger pinch works in every tool. Single-finger Select drags components; Pan moves the view.
- Searchable, categorized component browser with defaults, terminal counts and 13 working components: resistor, capacitor, inductor, voltage source, current source, ground, switch, potentiometer, diode, LED, Zener diode, NPN and PNP transistor.
- Select a component to edit, rotate, duplicate or delete it. Double-tap opens its editor; double-tapping a switch toggles it. SI values such as 4.7k, 22u and 10m are accepted.
- Tap two terminal circles or drag between them in Wire mode. Crossed wires join only through an actual shared terminal. Three-pin devices expose individually labeled terminals.
- DC operating point and RC/RL/RLC transient response, including voltage/current/power waveforms, signed readings, transistor base current and VBE, switch/diode state, and potentiometer wiper voltage.
- Nine connected starter circuits: divider, parallel branches, RC, RL, LED, Zener, switch, adjustable divider and NPN stage.
- Named projects on the device, undo/redo, automatic draft recovery, JSON import/export and CSV output through the clipboard.

## Current animation

Run calculates the circuit and keeps the editor visible. Soft current particles and fading trails move in the conventional current direction. Connected series segments form continuous streams, including through resistor, inductor, potentiometer and transistor symbol geometry. The pause/play button freezes or resumes them; the speed menu offers 0.5×, 1× and 2× playback. Particle speed indicates relative current magnitude; it is not electron drift speed. Branches below 1 nA remain still, including open-switch leakage.

Signed per-terminal and wire currents come from C++, including the three pins of potentiometers and BJTs. C++ identifies graph bridges to calculate unique ideal-wire currents. Redundant ideal-wire loops have no unique current division, so those individual loop wires remain still rather than showing an invented distribution.

Animation stops when the editor is hidden, when the app is backgrounded, or when the system requests reduced motion. Changing a circuit invalidates its old flow. A simulated switch can be double-tapped to toggle and immediately recalculate the flow. For transient analysis, the editor displays current from the final sample; the complete waveform remains on Results.

## Electrical models

DC treats capacitors as open and inductors as ideal shorts. Transient uses backward Euler with zero initial capacitor voltage and inductor current; independent sources switch on at t = 0. The UI uses 200 time steps; the native API accepts up to 1000.

Switches use 1 mΩ closed and 1 TΩ open. A potentiometer is a three-terminal resistive divider with a 0–100% wiper position. Diode and LED forward-voltage settings specify voltage at 1 mA, using an exponential junction model. Zener reverse breakdown uses a 10 Ω incremental slope. NPN/PNP transistors use an educational Ebers–Moll model with configurable forward gain and fixed junction parameters. These models do not include capacitance, temperature effects, device-specific SPICE parameters or thermal failure.

The solver uses modified nodal analysis, pivoted Gaussian elimination and damped Newton iterations for nonlinear devices. Unsupported features include AC sweeps, arbitrary waveforms, MOSFETs and op-amps. Limits: 128 components, 512 wires, 2 MB project JSON.

## OOP design

Component is an abstract C++ class with private data, virtual type/validate/stamp/current methods and a virtual destructor. Concrete component classes override electrical behavior. Circuit owns components through unique_ptr and owns Node/Wire objects by composition. SimulationEngine assembles and solves the model; ProjectManager uses fstream for JSON files. The C ABI returns allocated UTF-8 responses and Dart releases each one with sc_free. Flutter runs native requests in worker isolates.

See docs/architecture.md for implementation details. The browser preview is a separate earlier design with a smaller reference component set; the Android app is the current product.

## Verification

Version 0.5 passes 27 Flutter tests and clean Dart analysis. Release verification details are recorded in docs/ui-validation.json. Native tests cover 2,062 original checks plus 3,042 extended semiconductor, switch, potentiometer, RL and RLC checks and 734 wire-current direction, branching, KCL and ambiguity checks. Flutter tests include real C++ FFI and all nine packaged examples, small/landscape layouts, large text, pinch zoom, editing, searching, save/load and recovery.

Version 0.2 was confirmed working on the user's physical Android phone. The 0.3 release is checked through automated native/UI tests and APK inspection; no physical device or emulator is attached to this build session.

## Build verification locally

Run flutter analyze and flutter test with a desktop C++ toolchain. CMake builds core_tests and extended_core_tests; ctest runs both. On Windows without Visual Studio, tools/test_host_windows.ps1 can build the same core with LLVM-MinGW and then run Flutter tests. The Android build always compiles source through the NDK.

The supplied Android integration smoke test checks startup, C++ loading, simulation and saving on an attached Android device. The component library, project gallery and results screens share the same visual system; starter projects include previews of their actual schematics. DC results include node-voltage bars, while transient results retain selectable voltage/current/power waveforms. The GitHub Actions workflow has not been executed from this session.

Recovery is best effort: Android may terminate the app before a pending write completes. Use Save for a named copy.

Bundled fonts are distributed under the SIL Open Font License. Copyright and full license notices are included in assets/fonts/ and in the Android asset bundle. Native numerical code is unchanged from the previously verified 0.4 core; its 5,838 numerical checks remain applicable.
