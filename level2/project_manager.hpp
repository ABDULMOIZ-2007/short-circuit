#ifndef SHORT_CIRCUIT_LEVEL2_PROJECT_MANAGER_HPP
#define SHORT_CIRCUIT_LEVEL2_PROJECT_MANAGER_HPP

#include "circuit.hpp"
#include <fstream>
#include <iomanip>
#include <limits>

namespace short_circuit {

class ProjectManager {
public:
    void save(const Circuit& circuit, const std::string& path) const {
        std::ofstream file(path);
        if (!file) throw std::runtime_error("Cannot open project for writing.");

        file << "SHORT_CIRCUIT_DC 1\n";
        file << std::setprecision(std::numeric_limits<double>::max_digits10);
        const auto& nodes = circuit.getNodes();
        for (std::size_t i = 1; i < nodes.size(); ++i)
            file << "N " << std::quoted(nodes[i].name) << '\n';
        for (const Wire& wire : circuit.getWires())
            file << "W " << wire.from << ' ' << wire.to << '\n';
        for (const auto& part : circuit.getParts()) {
            file << part->type() << ' ' << std::quoted(part->name()) << ' '
                 << part->positive() << ' ' << part->negative() << ' '
                 << part->value() << '\n';
        }
        file.close();
        if (!file) throw std::runtime_error("Could not finish saving the project.");
    }

    Circuit load(const std::string& path) const {
        std::ifstream file(path);
        std::string header;
        if (!std::getline(file, header) || header != "SHORT_CIRCUIT_DC 1")
            throw std::runtime_error("Cannot read the DC project header.");

        Circuit circuit;
        char kind;
        while (file >> kind) {
            std::string name;
            int p, n;
            double value;
            if (kind == 'N' && file >> std::quoted(name)) {
                circuit.addNode(name);
            } else if (kind == 'W' && file >> p >> n) {
                circuit.connect(p, n);
            } else if ((kind == 'R' || kind == 'V' || kind == 'G') &&
                       file >> std::quoted(name) >> p >> n >> value) {
                if (kind == 'R')
                    circuit.add(std::make_unique<Resistor>(name, p, n, value));
                else if (kind == 'V')
                    circuit.add(std::make_unique<VoltageSource>(name, p, n, value));
                else if (n == 0 && value == 0.0)
                    circuit.add(std::make_unique<Ground>(name, p));
                else
                    throw std::runtime_error("Invalid ground record.");
            } else {
                throw std::runtime_error("Invalid DC project record.");
            }
        }
        if (file.bad()) throw std::runtime_error("Could not finish reading the project.");
        return circuit;
    }
};

} // namespace short_circuit

#endif
