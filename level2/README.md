# Short Circuit Level 2 | C++17 demo

This preliminary DC implementation reproduces the voltage divider from the Flutter app using a compact C++ program. The mobile app uses the full native engine under packages/short_circuit_core/src. The demo builds independently and uses the C++ standard library.

## Compile and run

Open a terminal in this directory with a C++17 compiler available.

~~~powershell
g++ -std=c++17 -Wall -Wextra main.cpp -o short-circuit-dc.exe
.\short-circuit-dc.exe
~~~

On Linux or macOS, use -o short-circuit-dc and run ./short-circuit-dc. You can use clang++ in place of g++. In Code::Blocks, add main.cpp and its headers to a C++ console project and select C++17.

The demo writes divider.dc.txt in the working directory. Pass a different path as the first argument to choose the output file. It then reloads that file and solves the restored circuit.

~~~text
Short Circuit | 12 V divider
Supply = 12.000 V
Tap    = 8.000 V
R1 current = 4.000 mA
Reloaded tap = 8.000 V
Validation: Resistance must be finite and positive.
~~~

## Read in this order

1. main.cpp builds the 12 V divider with 1 kÎ© and 2 kÎ© resistors and prints the result.
2. circuit.hpp defines the circuit, components, nodes and wires. Follow Circuit::add, Circuit::connect and the virtual stamp call in solveDC.
3. project_manager.hpp shows how C++ saves and reconstructs the circuit with file streams.
4. linear_system.hpp holds the matrix routine. Resistors contribute 1/R. Voltage sources contribute a voltage equation. Ground uses a 0 V constraint to the reference.

See class-diagram.png for the UML. Filled diamonds show Circuit ownership. The hollow triangle points to Component. Dashed arrows show dependencies. Node and Wire are C++ structs, which are class types with public access by default.

| Concept | Example |
| --- | --- |
| Abstraction | Component defines pure virtual type, value and stamp methods. |
| Inheritance | Resistor, VoltageSource and Ground publicly derive from Component. |
| Runtime polymorphism | The solveDC loop calls the correct stamp override through a base pointer. |
| Encapsulation | Resistor::ohms is private, and setResistance rejects invalid values. |
| Composition | Circuit owns its nodes, wires and polymorphic components. |
| Construction and destruction | Initializer lists set terminal IDs. unique_ptr and a virtual destructor manage component lifetime. |
| File and exception handling | ProjectManager uses file streams, and main catches input or I/O errors. |

During the viva, start at main.cpp. Changing R2 from 2 kÎ© to 1 kÎ© changes the tap from 8 V to 6 V. Show the schematic and animated current on the Android app using the matching Voltage divider example.

## Scope

The demo covers linear DC circuits with resistors, ideal voltage sources, wires and a ground reference. It assumes a unique solution and uses a fixed pivot tolerance appropriate for the supplied teaching circuit. The demo's text files and the Flutter app's JSON files use separate formats. See ../MOBILE_BUILD.md for the mobile setup.
