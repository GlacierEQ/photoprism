#include "benchmark_framework.h"
#include <thread>
#include <cmath>

// Example function to benchmark
double compute_pi(int iterations) {
    double sum = 0.0;
    for (int i = 0; i < iterations; i++) {
        double term = (i % 2 == 0) ? 1.0 : -1.0;
        term /= (2.0 * i + 1.0);
        sum += term;
    }
    return 4.0 * sum;
}

int main() {
    // Create benchmark suite
    BenchmarkFramework framework("PhotoPrism");

    // Add benchmarks with different workloads
    framework.add_benchmark("Low workload calculation", []() {
        compute_pi(10000);
    }, 20, 5);

    framework.add_benchmark("Medium workload calculation", []() {
        compute_pi(100000);
    }, 15, 3);

    framework.add_benchmark("High workload calculation", []() {
        compute_pi(1000000);
    }, 10, 2);

    // Add a benchmark with sleep to simulate I/O
    framework.add_benchmark("I/O simulation", []() {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }, 5, 1);

    // Run all benchmarks
    framework.run_all_benchmarks();

    return 0;
}
