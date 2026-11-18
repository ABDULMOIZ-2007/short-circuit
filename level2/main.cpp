#include "project_manager.hpp"
#include <iostream>

using namespace short_circuit;

int main(int argc, char* argv[]) {
    const std::string path = argc > 1 ? argv[1] : "divider.dc.txt";
    try {
        Circuit circuit;
        const int supply = circuit.addNode("Supply");
        const int tap = circuit.addNode("Tap");
        const int returnNode = circuit.addNode("Return");
        const int groundPin = circuit.addNode("Ground pin");

        circuit.add(std::make_unique<VoltageSource>("V1", supply, returnNode, 12.0));
        const double r1Ohms = 1000.0;
        circuit.add(std::make_unique<Resistor>("R1", supply, tap, r1Ohms));
        circuit.add(std::make_unique<Resistor>("R2", tap, returnNode, 2000.0));
        circuit.add(std::make_unique<Ground>("GND", groundPin));
        circuit.connect(groundPin, returnNode);

        const auto voltages = circuit.solveDC();
        std::cout << std::fixed << std::setprecision(3);
        std::cout << "Short Circuit | 12 V divider\n";
        std::cout << "Supply = " << voltages[supply] << " V\n";
        std::cout << "Tap    = " << voltages[tap] << " V\n";

        const double drop = voltages[supply] - voltages[tap];
        std::cout << "R1 current = " << 1000.0 * drop / r1Ohms << " mA\n";

        ProjectManager projects;
        projects.save(circuit, path);
        Circuit restored = projects.load(path);
        std::cout << "Reloaded tap = " << restored.solveDC()[tap] << " V\n";

        try {
            Resistor invalid("Invalid", supply, tap, 0.0);
        } catch (const std::invalid_argument& problem) {
            std::cout << "Validation: " << problem.what() << '\n';
        }
    } catch (const std::exception& problem) {
        std::cerr << "Error: " << problem.what() << '\n';
        return 1;
    }
}
