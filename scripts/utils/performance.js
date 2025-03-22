const { performance } = require('perf_hooks');
const fs = require('fs').promises;
const path = require('path');
const os = require('os');
const logger = require('./logger');

/**
 * Performance benchmarking utility
 * Helps measure and analyze code performance
 */
class PerformanceBenchmark {
  /**
   * Create a new benchmark instance
   * @param {Object} options - Benchmark options
   */
  constructor(options = {}) {
    this.logger = logger.getLogger('performance');
    this.options = {
      logResults: true,
      saveResults: true,
      resultsDir: path.resolve(__dirname, '../../performance'),
      compareWithPrevious: true,
      ...options
    };

    this.benchmarks = {};
    this.activeMarkers = {};
    this.memorySnapshots = {};
    this.currentTest = null;
  }

  /**
   * Ensure results directory exists
   * @returns {Promise<void>}
   */
  async ensureResultsDirectory() {
    if (this.options.saveResults) {
      try {
        await fs.access(this.options.resultsDir);
      } catch {
        await fs.mkdir(this.options.resultsDir, { recursive: true });
      }
    }
  }

  /**
   * Start a benchmark test
   * @param {string} name - Test name
   * @returns {PerformanceBenchmark} this instance for chaining
   */
  startTest(name) {
    if (this.currentTest) {
      this.logger.warn(`Test "${this.currentTest}" was not ended before starting "${name}"`);
      this.endTest();
    }

    this.logger.debug(`Starting benchmark test: ${name}`);
    this.currentTest = name;
    this.benchmarks[name] = {
      startTime: Date.now(),
      markers: {},
      memoryUsage: this.captureMemoryUsage(),
      counters: {},
      system: this.captureSystemInfo()
    };

    return this;
  }

  /**
   * Mark a point in the benchmark
   * @param {string} markerName - Marker name
   * @returns {PerformanceBenchmark} this instance for chaining
   */
  mark(markerName) {
    if (!this.currentTest) {
      this.logger.warn(`Cannot mark "${markerName}" - no active test`);
      return this;
    }

    const fullMarkerName = `${this.currentTest}:${markerName}`;
    const now = performance.now();
    this.activeMarkers[fullMarkerName] = now;

    this.logger.debug(`Marking point: ${markerName}`);

    return this;
  }

  /**
   * Measure time between two markers
   * @param {string} markerName - Marker name
   * @param {string} [startMarker=null] - Start marker name (optional)
   * @returns {number} Time elapsed in milliseconds
   */
  measure(markerName, startMarker = null) {
    if (!this.currentTest) {
      this.logger.warn(`Cannot measure "${markerName}" - no active test`);
      return -1;
    }

    const now = performance.now();
    let elapsed;

    if (startMarker) {
      const fullStartMarker = `${this.currentTest}:${startMarker}`;
      const startTime = this.activeMarkers[fullStartMarker];

      if (!startTime) {
        this.logger.warn(`Start marker "${startMarker}" not found`);
        return -1;
      }

      elapsed = now - startTime;
    } else {
      const fullMarkerName = `${this.currentTest}:${markerName}`;
      const startTime = this.activeMarkers[fullMarkerName];

      if (!startTime) {
        this.logger.warn(`Marker "${markerName}" not found`);
        return -1;
      }

      elapsed = now - startTime;

      // Clear the marker after measuring
      delete this.activeMarkers[fullMarkerName];
    }

    // Record the measurement
    if (!this.benchmarks[this.currentTest].markers[markerName]) {
      this.benchmarks[this.currentTest].markers[markerName] = [];
    }

    this.benchmarks[this.currentTest].markers[markerName].push(elapsed);

    this.logger.debug(`Measured ${markerName}: ${elapsed.toFixed(3)}ms`);

    return elapsed;
  }

  /**
   * Start measuring an operation
   * @param {string} name - Operation name
   * @returns {Function} Function to call when operation completes
   */
  measureOperation(name) {
    if (!this.currentTest) {
      this.logger.warn(`Cannot measure operation "${name}" - no active test`);
      return () => {};
    }

    const operationMarker = `operation:${name}`;
    this.mark(operationMarker);

    return () => this.measure(name, operationMarker);
  }

  /**
   * Take a memory snapshot
   * @param {string} name - Snapshot name
   * @returns {Object} Memory usage information
   */
  takeMemorySnapshot(name) {
    if (!this.currentTest) {
      this.logger.warn(`Cannot take memory snapshot "${name}" - no active test`);
      return null;
    }

    const snapshot = this.captureMemoryUsage();

    if (!this.benchmarks[this.currentTest].memorySnapshots) {
      this.benchmarks[this.currentTest].memorySnapshots = {};
    }

    this.benchmarks[this.currentTest].memorySnapshots[name] = snapshot;
    return snapshot;
  }

  /**
   * Increment a counter
   * @param {string} counter - Counter name
   * @param {number} [increment=1] - Value to increment by
   * @returns {number} New counter value
   */
  incrementCounter(counter, increment = 1) {
    if (!this.currentTest) {
      this.logger.warn(`Cannot increment counter "${counter}" - no active test`);
      return 0;
    }

    const counters = this.benchmarks[this.currentTest].counters;
    counters[counter] = (counters[counter] || 0) + increment;

    return counters[counter];
  }

  /**
   * Capture memory usage information
   * @returns {Object} Memory usage details
   * @private
   */
  captureMemoryUsage() {
    const memoryUsage = process.memoryUsage();
    return {
      rss: memoryUsage.rss,
      heapTotal: memoryUsage.heapTotal,
      heapUsed: memoryUsage.heapUsed,
      external: memoryUsage.external,
      timestamp: Date.now()
    };
  }

  /**
   * Capture system information
   * @returns {Object} System information
   * @private
   */
  captureSystemInfo() {
    return {
      platform: os.platform(),
      release: os.release(),
      hostname: os.hostname(),
      cpus: os.cpus().length,
      totalMemory: os.totalmem(),
      freeMemory: os.freemem(),
      uptime: os.uptime(),
      loadAvg: os.loadavg()
    };
  }

  /**
   * End the current benchmark test
   * @returns {Object} Benchmark results
   */
  async endTest() {
    if (!this.currentTest) {
      this.logger.warn('No active test to end');
      return null;
    }

    const testName = this.currentTest;
    const benchmark = this.benchmarks[testName];

    // Calculate duration
    benchmark.endTime = Date.now();
    benchmark.duration = benchmark.endTime - benchmark.startTime;

    // Take a final memory snapshot
    benchmark.endMemoryUsage = this.captureMemoryUsage();
    benchmark.memoryDelta = {
      rss: benchmark.endMemoryUsage.rss - benchmark.memoryUsage.rss,
      heapTotal: benchmark.endMemoryUsage.heapTotal - benchmark.memoryUsage.heapTotal,
      heapUsed: benchmark.endMemoryUsage.heapUsed - benchmark.memoryUsage.heapUsed,
      external: benchmark.endMemoryUsage.external - benchmark.memoryUsage.external
    };

    // Process marker statistics
    for (const marker in benchmark.markers) {
      const measurements = benchmark.markers[marker];

      if (measurements.length > 0) {
        // Calculate statistics
        const sum = measurements.reduce((a, b) => a + b, 0);
        const avg = sum / measurements.length;
        const min = Math.min(...measurements);
        const max = Math.max(...measurements);

        // Calculate standard deviation
        const squaredDiffs = measurements.map(value => (value - avg) ** 2);
        const avgSquaredDiff = squaredDiffs.reduce((a, b) => a + b, 0) / measurements.length;
        const stdDev = Math.sqrt(avgSquaredDiff);

        // Replace raw measurements with statistics
        benchmark.markers[marker] = {
          measurements: measurements.length,
          average: avg,
          min,
          max,
          stdDev,
          total: sum
        };
      }
    }

    // Log results
    if (this.options.logResults) {
      this.logResults(testName, benchmark);
    }

    // Save results
    if (this.options.saveResults) {
      await this.saveResults(testName, benchmark);
    }

    this.logger.info(`Benchmark test "${testName}" completed in ${benchmark.duration}ms`);
    this.currentTest = null;

    return benchmark;
  }

  /**
   * Log benchmark results
   * @param {string} testName - Test name
   * @param {Object} benchmark - Benchmark results
   * @private
   */
  logResults(testName, benchmark) {
    this.logger.info(`\n=== Benchmark Results: ${testName} ===`);
    this.logger.info(`Total Duration: ${benchmark.duration}ms`);

    if (Object.keys(benchmark.markers).length > 0) {
      this.logger.info('\nMarker Performance:');
      for (const marker in benchmark.markers) {
        const stats = benchmark.markers[marker];
        this.logger.info(` - ${marker}: avg=${stats.average.toFixed(2)}ms, min=${stats.min.toFixed(2)}ms, max=${stats.max.toFixed(2)}ms, runs=${stats.measurements}`);
      }
    }

    if (Object.keys(benchmark.counters).length > 0) {
      this.logger.info('\nCounters:');
      for (const counter in benchmark.counters) {
        this.logger.info(` - ${counter}: ${benchmark.counters[counter]}`);
      }
    }

    this.logger.info('\nMemory Usage:');
    this.logger.info(` - Start: ${(benchmark.memoryUsage.heapUsed / 1024 / 1024).toFixed(2)} MB`);
    this.logger.info(` - End: ${(benchmark.endMemoryUsage.heapUsed / 1024 / 1024).toFixed(2)} MB`);
    this.logger.info(` - Delta: ${(benchmark.memoryDelta.heapUsed / 1024 / 1024).toFixed(2)} MB`);
    this.logger.info('===============================\n');
  }

  /**
   * Save benchmark results to file
   * @param {string} testName - Test name
   * @param {Object} benchmark - Benchmark results
   * @returns {Promise<void>}
   * @private
   */
  async saveResults(testName, benchmark) {
    try {
      await this.ensureResultsDirectory();

      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      const filename = `${testName.replace(/\s+/g, '-')}-${timestamp}.json`;
      const filePath = path.join(this.options.resultsDir, filename);

      await fs.writeFile(filePath, JSON.stringify(benchmark, null, 2), 'utf8');
      this.logger.debug(`Benchmark results saved to ${filePath}`);

      if (this.options.compareWithPrevious) {
        await this.compareWithPreviousResults(testName, benchmark);
      }
    } catch (error) {
      this.logger.error(`Failed to save benchmark results: ${error.message}`);
    }
  }

  /**
   * Compare current results with previous benchmarks
   * @param {string} testName - Test name
   * @param {Object} currentBenchmark - Current benchmark results
   * @returns {Promise<void>}
   * @private
   */
  async compareWithPreviousResults(testName, currentBenchmark) {
    try {
      const files = await fs.readdir(this.options.resultsDir);
      const pattern = new RegExp(`^${testName.replace(/\s+/g, '-')}-.*\\.json$`);
      const previousFiles = files
        .filter(file => pattern.test(file) && !file.includes(new Date().toISOString().substring(0, 10)))
        .sort()
        .slice(-5); // Get up to 5 recent previous results

      if (previousFiles.length === 0) {
        return;
      }

      this.logger.info('\n=== Performance Comparison ===');

      for (const file of previousFiles) {
        const filePath = path.join(this.options.resultsDir, file);
        const content = await fs.readFile(filePath, 'utf8');
        const previousBenchmark = JSON.parse(content);

        const durationDiff = ((currentBenchmark.duration - previousBenchmark.duration) / previousBenchmark.duration) * 100;
        this.logger.info(`\nComparison with ${file}:`);
        this.logger.info(`Duration: ${previousBenchmark.duration}ms → ${currentBenchmark.duration}ms (${durationDiff.toFixed(2)}%)`);

        // Compare markers
        for (const marker in currentBenchmark.markers) {
          if (previousBenchmark.markers && previousBenchmark.markers[marker]) {
            const current = currentBenchmark.markers[marker].average;
            const previous = previousBenchmark.markers[marker].average;
            const diff = ((current - previous) / previous) * 100;
            const trend = diff > 0 ? 'slower' : 'faster';

            this.logger.info(`Marker "${marker}": ${previous.toFixed(2)}ms → ${current.toFixed(2)}ms (${Math.abs(diff).toFixed(2)}% ${trend})`);
          }
        }

        // Compare memory
        if (previousBenchmark.memoryDelta && currentBenchmark.memoryDelta) {
          const prevMemory = previousBenchmark.memoryDelta.heapUsed / 1024 / 1024;
          const currMemory = currentBenchmark.memoryDelta.heapUsed / 1024 / 1024;
          const memDiff = ((currMemory - prevMemory) / prevMemory) * 100;
          const memTrend = memDiff > 0 ? 'more' : 'less';

          this.logger.info(`Memory Delta: ${prevMemory.toFixed(2)}MB → ${currMemory.toFixed(2)}MB (${Math.abs(memDiff).toFixed(2)}% ${memTrend})`);
        }
      }

      this.logger.info('============================\n');
    } catch (error) {
      this.logger.error(`Failed to compare with previous results: ${error.message}`);
    }
  }

  /**
   * Run a function with benchmarking
   * @param {string} name - Benchmark name
   * @param {Function} fn - Function to run
   * @param {Object} [options={}] - Options
   * @returns {Promise<any>} Function result
   */
  async run(name, fn, options = {}) {
    this.startTest(name);

    try {
      const result = typeof fn === 'function' ? await fn() : fn;
      await this.endTest();
      return result;
    } catch (error) {
      this.logger.error(`Benchmark "${name}" failed: ${error.message}`);
      await this.endTest();
      throw error;
    }
  }

  /**
   * Create a decorator to benchmark a function
   * @param {string} name - Benchmark name
   * @returns {Function} Decorator function
   */
  static benchmark(name) {
    return function(target, key, descriptor) {
      const originalMethod = descriptor.value;
      const benchmarkInstance = new PerformanceBenchmark();

      descriptor.value = async function(...args) {
        return benchmarkInstance.run(`${name || key}`, async () => {
          return await originalMethod.apply(this, args);
        });
      };

      return descriptor;
    };
  }
}

module.exports = PerformanceBenchmark;
