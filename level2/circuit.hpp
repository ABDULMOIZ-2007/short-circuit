#ifndef SHORT_CIRCUIT_LEVEL2_HPP
#define SHORT_CIRCUIT_LEVEL2_HPP

#include "linear_system.hpp"
#include <cmath>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace short_circuit {

struct Node {
    std::string name;
};

struct Wire {
    int from;
    int to;
};

class Component {
    std::string label;
    int positiveNode;
    int negativeNode;

protected:
    Component(std::string name, int p, int n)
        : label(std::move(name)), positiveNode(p), negativeNode(n) {}

public:
    virtual ~Component() = default;

    const std::string& name() const { return label; }
    int positive() const { return positiveNode; }
    int negative() const { return negativeNode; }

    virtual char type() const = 0;
    virtual double value() const = 0;
    virtual void stamp(LinearSystem& system, int p, int n) const = 0;
};

class Resistor : public Component {
    double ohms;

public:
    Resistor(std::string name, int p, int n, double resistance)
        : Component(std::move(name), p, n) {
        setResistance(resistance);
    }

    void setResistance(double resistance) {
        if (!std::isfinite(resistance) || resistance <= 0.0)
            throw std::invalid_argument("Resistance must be finite and positive.");
        ohms = resistance;
    }

    char type() const override { return 'R'; }
    double value() const override { return ohms; }

    void stamp(LinearSystem& system, int p, int n) const override {
        system.conductance(p, n, 1.0 / ohms);
    }
};

class VoltageSource : public Component {
    double volts;

public:
    VoltageSource(std::string name, int p, int n, double voltage)
        : Component(std::move(name), p, n), volts(voltage) {
        if (!std::isfinite(voltage))
            throw std::invalid_argument("Voltage must be finite.");
    }

    char type() const override { return 'V'; }
    double value() const override { return volts; }

    void stamp(LinearSystem& system, int p, int n) const override {
        system.voltage(p, n, volts);
    }
};

class Ground : public Component {
public:
    Ground(std::string name, int node) : Component(std::move(name), node, 0) {}

    char type() const override { return 'G'; }
    double value() const override { return 0.0; }

    void stamp(LinearSystem& system, int p, int n) const override {
        system.voltage(p, n, 0.0);
    }
};

class Circuit {
    std::vector<Node> nodes{{"Reference"}};
    std::vector<Wire> wires;
    std::vector<std::unique_ptr<Component>> parts;

    void checkNode(int id) const {
        if (id <= 0 || id >= static_cast<int>(nodes.size()))
            throw std::invalid_argument("Unknown circuit node.");
    }

public:
    int addNode(const std::string& name) {
        nodes.push_back({name});
        return static_cast<int>(nodes.size()) - 1;
    }

    void connect(int from, int to) {
        checkNode(from);
        checkNode(to);
        wires.push_back({from, to});
    }

    void add(std::unique_ptr<Component> part) {
        if (!part) throw std::invalid_argument("Missing component.");
        checkNode(part->positive());
        if (part->type() != 'G') checkNode(part->negative());
        parts.push_back(std::move(part));
    }

    const std::vector<Node>& getNodes() const { return nodes; }
    const std::vector<Wire>& getWires() const { return wires; }
    const std::vector<std::unique_ptr<Component>>& getParts() const { return parts; }

    std::vector<double> solveDC() const {
        const int count = static_cast<int>(nodes.size());
        std::vector<int> net(count);
        for (int i = 0; i < count; ++i) net[i] = i;

        // A wire makes both endpoints part of the same electrical net.
        for (const Wire& wire : wires) {
            const int oldNet = net[wire.to];
            const int newNet = net[wire.from];
            for (int& id : net) {
                if (id == oldNet) id = newNet;
            }
        }

        // Allocate one voltage unknown per net, regardless of wire count.
        std::vector<int> index(count, 0);
        int next = 1;
        for (int i = 1; i < count; ++i) {
            int& id = index[net[i]];
            if (id == 0) id = next++;
            net[i] = id;
        }

        LinearSystem system(next);
        for (const auto& part : parts)
            part->stamp(system, net[part->positive()], net[part->negative()]);

        const auto solution = system.solve();
        std::vector<double> voltages(count);
        for (int i = 1; i < count; ++i)
            voltages[i] = solution[net[i]];
        return voltages;
    }
};

} // namespace short_circuit

#endif
