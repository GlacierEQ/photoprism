#pragma once

#include <chrono>
#include <functional>
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <numeric>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <memory>

/**
 * @brief Professional benchmarking framework
 *
 * This framework provides accurate performance measurement, statistical analysis,
 * and reporting capabilities for component benchmarking.
 */
class BenchmarkFramework {
public:
    struct BenchmarkResult {
        std::string name;
        std::vector<double> iterations_ms;
        double min_ms;
        double max_ms;
        double mean_ms;
        double median_ms;
        double stddev_ms;
    };

    BenchmarkFramework(const std::string& suite_name)
        : suite_name_(suite_name) {
        std::cout << "🔍 Initializing benchmark suite: " << suite_name << std::endl;
    }

    void add_benchmark(const std::string& name, std::function<void()> func,
                      int iterations = 10, int warmup_iterations = 3) {
        benchmarks_.push_back({name, func, iterations, warmup_iterations});
    }

    void run_all_benchmarks() {
        std::vector<BenchmarkResult> results;

        std::cout << "\n⏱️ Running benchmark suite: " << suite_name_ << "\n";
        std::cout << "═════════════════════════════════════════════════════\n";

        for (const auto& benchmark : benchmarks_) {
            BenchmarkResult result = run_single_benchmark(
                benchmark.name, benchmark.func,
                benchmark.iterations, benchmark.warmup_iterations
            );

            results.push_back(result);

            std::cout << "📊 " << std::left << std::setw(30) << result.name
                      << " │ " << std::right << std::fixed << std::setprecision(3)
                      << std::setw(8) << result.mean_ms << " ms"
                      << " │ [" << result.min_ms << " ms - " << result.max_ms << " ms]"
                      << " │ σ: " << result.stddev_ms << " ms"
                      << std::endl;
        }

        std::cout << "═════════════════════════════════════════════════════\n\n";

        // Save results to files
        save_results_csv(results);
        save_results_json(results);

        std::cout << "Results saved to " << suite_name_ << "_benchmark_results.csv and "
                  << suite_name_ << "_benchmark_results.json" << std::endl;
    }

private:
    struct BenchmarkInfo {
        std::string name;
        std::function<void()> func;
        int iterations;
        int warmup_iterations;
    };

    std::string suite_name_;
    std::vector<BenchmarkInfo> benchmarks_;

    BenchmarkResult run_single_benchmark(
        const std::string& name,
        std::function<void()> func,
        int iterations,
        int warmup_iterations
    ) {
        BenchmarkResult result;
        result.name = name;
        result.iterations_ms.reserve(iterations);

        std::cout << "Running benchmark: " << name << std::endl;

        // Warmup phase
        for (int i = 0; i < warmup_iterations; ++i) {
            func(); // Run but don't measure
        }

        // Measurement phase
        for (int i = 0; i < iterations; ++i) {
            auto start = std::chrono::high_resolution_clock::now();

            func();

            auto end = std::chrono::high_resolution_clock::now();
            double duration = std::chrono::duration<double, std::milli>(end - start).count();
            result.iterations_ms.push_back(duration);
        }

        // Calculate statistics
        result.min_ms = *std::min_element(result.iterations_ms.begin(), result.iterations_ms.end());
        result.max_ms = *std::max_element(result.iterations_ms.begin(), result.iterations_ms.end());

        result.mean_ms = std::accumulate(
            result.iterations_ms.begin(), result.iterations_ms.end(), 0.0
        ) / result.iterations_ms.size();

        // Calculate median
        std::vector<double> sorted = result.iterations_ms;
        std::sort(sorted.begin(), sorted.end());
        if (sorted.size() % 2 == 0) {
            result.median_ms = (sorted[sorted.size() / 2 - 1] + sorted[sorted.size() / 2]) / 2.0;
        } else {
            result.median_ms = sorted[sorted.size() / 2];
        }

        // Calculate standard deviation
        double variance = 0.0;
        for (const auto& time : result.iterations_ms) {
            variance += (time - result.mean_ms) * (time - result.mean_ms);
        }
        variance /= result.iterations_ms.size();
        result.stddev_ms = std::sqrt(variance);

        return result;
    }

    void save_results_csv(const std::vector<BenchmarkResult>& results) {
        std::ofstream file(suite_name_ + "_benchmark_results.csv");

        file << "Benchmark,Mean (ms),Median (ms),Min (ms),Max (ms),StdDev (ms)" << std::endl;

        for (const auto& result : results) {
            file << "\"" << result.name << "\","
                 << result.mean_ms << ","
                 << result.median_ms << ","
                 << result.min_ms << ","
                 << result.max_ms << ","
                 << result.stddev_ms << std::endl;
        }
    }

    void save_results_json(const std::vector<BenchmarkResult>& results) {
        std::ofstream file(suite_name_ + "_benchmark_results.json");

        file << "{\n";
        file << "  \"suite\": \"" << suite_name_ << "\",\n";
        file << "  \"results\": [\n";

        for (size_t i = 0; i < results.size(); ++i) {
            const auto& result = results[i];

            file << "    {\n";
            file << "      \"name\": \"" << result.name << "\",\n";
            file << "      \"mean_ms\": " << result.mean_ms << ",\n";
            file << "      \"median_ms\": " << result.median_ms << ",\n";
            file << "      \"min_ms\": " << result.min_ms << ",\n";
            file << "      \"max_ms\": " << result.max_ms << ",\n";
            file << "      \"stddev_ms\": " << result.stddev_ms << ",\n";
            file << "      \"iterations\": [";

            for (size_t j = 0; j < result.iterations_ms.size(); ++j) {
                file << result.iterations_ms[j];
                if (j < result.iterations_ms.size() - 1) {
                    file << ", ";
                }
            }

            file << "]\n";
            file << "    }";

            if (i < results.size() - 1) {
                file << ",";
            }
            file << "\n";
        }

        file << "  ]\n";
        file << "}\n";
    }
};
