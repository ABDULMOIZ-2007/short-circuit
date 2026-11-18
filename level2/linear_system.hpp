#ifndef SHORT_CIRCUIT_LEVEL2_LINEAR_SYSTEM_HPP
#define SHORT_CIRCUIT_LEVEL2_LINEAR_SYSTEM_HPP

#include <cmath>
#include <stdexcept>
#include <utility>
#include <vector>

namespace short_circuit {

// Unknown 0 is the reference. Its voltage is always zero.
class LinearSystem {
    std::vector<std::vector<double>> matrix;
    std::vector<double> rhs;

    void add(int row, int column, double value) {
        if (row != 0 && column != 0) matrix[row][column] += value;
    }

public:
    explicit LinearSystem(int size)
        : matrix(size, std::vector<double>(size, 0.0)), rhs(size, 0.0) {}

    void conductance(int p, int n, double g) {
        add(p, p, g);
        add(n, n, g);
        add(p, n, -g);
        add(n, p, -g);
    }

    void voltage(int p, int n, double volts) {
        const int branch = static_cast<int>(rhs.size());
        for (auto& row : matrix) row.push_back(0.0);
        matrix.emplace_back(branch + 1, 0.0);
        rhs.push_back(volts);
        add(p, branch, 1.0);
        add(n, branch, -1.0);
        add(branch, p, 1.0);
        add(branch, n, -1.0);
    }

    // Eliminate below each pivot, then solve from the bottom row up.
    std::vector<double> solve() {
        const int size = static_cast<int>(rhs.size());
        for (int column = 1; column < size; ++column) {
            int pivot = column;
            for (int row = column + 1; row < size; ++row) {
                if (std::abs(matrix[row][column]) > std::abs(matrix[pivot][column]))
                    pivot = row;
            }
            if (std::abs(matrix[pivot][column]) < 1e-12)
                throw std::runtime_error("Circuit has no unique DC solution.");

            std::swap(matrix[pivot], matrix[column]);
            std::swap(rhs[pivot], rhs[column]);
            for (int row = column + 1; row < size; ++row) {
                const double factor = matrix[row][column] / matrix[column][column];
                for (int j = column; j < size; ++j)
                    matrix[row][j] -= factor * matrix[column][j];
                rhs[row] -= factor * rhs[column];
            }
        }

        std::vector<double> result(size, 0.0);
        for (int row = size - 1; row > 0; --row) {
            double value = rhs[row];
            for (int j = row + 1; j < size; ++j)
                value -= matrix[row][j] * result[j];
            result[row] = value / matrix[row][row];
        }
        return result;
    }
};

} // namespace short_circuit

#endif
