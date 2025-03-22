const path = require('path');
const fs = require('fs').promises;
const { execSync } = require('child_process');
const PerformanceBenchmark = require('./utils/performance');
const logger = require('./utils/logger');
const benchmarkConfig = require('../config/benchmarks-config');
const os = require('os');

/**
 * PhotoPrism benchmark runner
 * Executes performance benchmarks for critical system components
 */
class BenchmarkRunner {
  constructor(options = {}) {
    this.logger = logger.getLogger('benchmark-runner');
    this.options = {
      ...benchmarkConfig.settings,
      ...options
    };

    this.performance = new PerformanceBenchmark({
      logResults: this.options.logResults,
      saveResults: this.options.saveResults,
      resultsDir: this.options.resultsDir,
      compareWithPrevious: this.options.compareWithPrevious
    });

    // Environment detection
    this.environment = process.env.NODE_ENV || 'development';
    this.isProduction = this.environment === 'production';

    // Results storage
    this.results = {};
  }

  /**
   * Initialize benchmark environment
   */
  async initialize() {
    this.logger.info('Initializing benchmark runner...');

    // Create results directory if it doesn't exist
    try {
      await this.performance.ensureResultsDirectory();
    } catch (error) {
      this.logger.error(`Failed to create results directory: ${error.message}`);
      return false;
    }

    // Check if benchmarks are enabled
    if (!this.options.enabled) {
      this.logger.warn('Benchmarks are disabled in configuration');
      return false;
    }

    // Skip certain benchmarks in production
    if (this.isProduction) {
      this.logger.info('Running in production mode - some detailed benchmarks will be skipped');
    }

    return true;
  }

  /**
   * Run system resource benchmark
   */
  async benchmarkSystemResources() {
    return this.performance.run('system-resources', async () => {
      this.logger.info('Benchmarking system resources...');

      // Measure CPU load
      const startMark = this.performance.mark('cpu-test-start');

      // CPU intensive operation
      const endTime = Date.now() + 1000; // Run for 1 second
      let counter = 0;
      while (Date.now() < endTime) {
        Math.sqrt(Math.random() * 10000);
        counter++;
      }

      const cpuOps = counter;
      this.performance.measure('cpu-operations', 'cpu-test-start');

      // Measure memory operations
      this.performance.mark('memory-test-start');

      // Memory intensive operation
      const arrays = [];
      for (let i = 0; i < 10; i++) {
        arrays.push(Buffer.alloc(1024 * 1024)); // Allocate 1MB
        this.performance.takeMemorySnapshot(`memory-snapshot-${i}`);
      }

      // Clean up to avoid memory leaks in the benchmark itself
      arrays.length = 0;

      this.performance.measure('memory-operations', 'memory-test-start');

      // Measure disk operations
      this.performance.mark('disk-test-start');

      const testFile = path.join(os.tmpdir(), 'photoprism-benchmark-test.data');

      try {
        // Write test
        const data = Buffer.alloc(10 * 1024 * 1024); // 10MB
        await fs.writeFile(testFile, data);

        // Read test
        await fs.readFile(testFile);

        // Clean up
        await fs.unlink(testFile);
      } catch (error) {
        this.logger.warn(`Disk benchmark error: ${error.message}`);
      }

      this.performance.measure('disk-operations', 'disk-test-start');

      return {
        cpuOperations: cpuOps,
        cpuCores: os.cpus().length,
        totalMemory: os.totalmem(),
        freeMemory: os.freemem(),
        platform: os.platform(),
        release: os.release(),
        uptime: os.uptime()
      };
    });
  }

  /**
   * Benchmark Podman container startup
   */
  async benchmarkPodmanStartup() {
    return this.performance.run('podman-startup', async () => {
      this.logger.info('Benchmarking Podman container startup...');

      try {
        // Check if podman is available
        try {
          execSync('podman --version', { stdio: 'pipe' });
        } catch (error) {
          this.logger.warn('Podman not available, skipping container startup benchmark');
          return { skipped: true, reason: 'Podman not installed' };
        }

        // Start a simple container and measure time
        this.performance.mark('container-startup');

        execSync('podman run --rm hello-world', { stdio: 'pipe' });

        const startupTime = this.performance.measure('container-startup-time', 'container-startup');

        return {
          startupTime,
          containerImage: 'hello-world'
        };
      } catch (error) {
        this.logger.error(`Podman benchmark error: ${error.message}`);
        return { failed: true, error: error.message };
      }
    });
  }

  /**
   * Benchmark image processing performance
   */
  async benchmarkImageProcessing() {
    return this.performance.run('image-processing', async () => {
      this.logger.info('Benchmarking image processing capabilities...');

      const benchmarkImage = path.resolve(__dirname, '../assets/benchmark/sample-image.jpg');
      const outputImage = path.resolve(os.tmpdir(), 'benchmark-output.jpg');

      try {
        // Check if we have sample images for benchmarking
        try {
          await fs.access(benchmarkImage);
        } catch {
          this.logger.warn('Benchmark image not found, skipping image processing benchmark');
          return { skipped: true, reason: 'Sample image not found' };
        }

        // Check if ImageMagick is available
        try {
          execSync('convert --version', { stdio: 'pipe' });
        } catch {
          try {
            execSync('magick --version', { stdio: 'pipe' });
          } catch {
            this.logger.warn('ImageMagick not available, skipping image processing benchmark');
            return { skipped: true, reason: 'ImageMagick not installed' };
          }
        }

        // Benchmark image resize
        this.performance.mark('image-resize');

        try {
          execSync(`convert "${benchmarkImage}" -resize 50% "${outputImage}"`, { stdio: 'pipe' });
        } catch {
          try {
            execSync(`magick "${benchmarkImage}" -resize 50% "${outputImage}"`, { stdio: 'pipe' });
          } catch (error) {
            throw new Error(`Image conversion failed: ${error.message}`);
          }
        }

        const resizeTime = this.performance.measure('image-resize-time', 'image-resize');

        // Cleanup
        try {
          await fs.unlink(outputImage);
        } catch {
          // Ignore cleanup errors
        }

        return {
          resizeTime,
          imageFormat: 'JPEG',
          processingTool: 'ImageMagick'
        };
      } catch (error) {
        this.logger.error(`Image processing benchmark error: ${error.message}`);
        return { failed: true, error: error.message };
      }
    });
  }

  /**
   * Benchmark database operations
   */
  async benchmarkDatabaseOperations() {
    return this.performance.run('database-operations', async () => {
      this.logger.info('Simulating database operations benchmark...');

      // This is a simplified simulation as we don't have direct DB access here
      this.performance.mark('db-operations-start');

      // Simulate DB operations with file operations
      const dbDir = path.join(os.tmpdir(), 'photoprism-db-benchmark');
      const iterations = 100;

      try {
        // Create test directory
        await fs.mkdir(dbDir, { recursive: true });

        // Write operations
        this.performance.mark('db-write');
        for (let i = 0; i < iterations; i++) {
          await fs.writeFile(
            path.join(dbDir, `record-${i}.json`),
            JSON.stringify({ id: i, data: `Sample data ${i}`, timestamp: Date.now() })
          );
        }
        const writeTime = this.performance.measure('db-write-time', 'db-write');

        // Read operations
        this.performance.mark('db-read');
        const files = await fs.readdir(dbDir);
        for (const file of files) {
          const content = await fs.readFile(path.join(dbDir, file), 'utf8');
          const parsed = JSON.parse(content);
          if (!parsed.id) {
            throw new Error('Invalid record');
          }
        }
        const readTime = this.performance.measure('db-read-time', 'db-read');

        // Update operations
        this.performance.mark('db-update');
        for (let i = 0; i < iterations; i++) {
          const filePath = path.join(dbDir, `record-${i}.json`);
          const content = await fs.readFile(filePath, 'utf8');
          const record = JSON.parse(content);
          record.updated = true;
          record.timestamp = Date.now();
          await fs.writeFile(filePath, JSON.stringify(record));
        }
        const updateTime = this.performance.measure('db-update-time', 'db-update');

        // Delete operations
        this.performance.mark('db-delete');
        for (let i = 0; i < iterations; i++) {
          await fs.unlink(path.join(dbDir, `record-${i}.json`));
        }
        const deleteTime = this.performance.measure('db-delete-time', 'db-delete');

        // Cleanup
        try {
          await fs.rmdir(dbDir);
        } catch {
          // Best effort cleanup
        }

        const totalTime = this.performance.measure('db-total-time', 'db-operations-start');

        return {
          writeTime,
          readTime,
          updateTime,
          deleteTime,
          totalTime,
          iterations,
          operationsPerSecond: Math.floor(iterations * 4 / (totalTime / 1000)) // CRUD ops/sec
        };
      } catch (error) {
        this.logger.error(`Database benchmark error: ${error.message}`);

        // Cleanup on error
        try {
          await fs.rm(dbDir, { recursive: true, force: true });
        } catch {
          // Ignore cleanup errors
        }

        return { failed: true, error: error.message };
      }
    });
  }

  /**
   * Benchmark network operations
   */
  async benchmarkNetworkOperations() {
    return this.performance.run('network-operations', async () => {
      this.logger.info('Benchmarking network operations...');

      try {
        const http = require('http');
        const https = require('https');

        // Test HTTP requests to well-known endpoints
        const endpoints = [
          { url: 'https://www.google.com', name: 'google' },
          { url: 'https://www.github.com', name: 'github' },
          { url: 'https://www.cloudflare.com', name: 'cloudflare' }
        ];

        const results = {};

        for (const endpoint of endpoints) {
          this.performance.mark(`request-${endpoint.name}`);

          await new Promise((resolve, reject) => {
            const requestLib = endpoint.url.startsWith('https') ? https : http;
            const req = requestLib.get(endpoint.url, (res) => {
              let data = '';
              res.on('data', chunk => { data += chunk; });
              res.on('end', () => {
                resolve({
                  statusCode: res.statusCode,
                  headers: res.headers,
                  dataSize: data.length
                });
              });
            });

            req.on('error', (error) => {
              reject(error);
            });

            req.end();
          });

          results[endpoint.name] = this.performance.measure(
            `request-${endpoint.name}-time`,
            `request-${endpoint.name}`
          );
        }

        return {
          endpoints: endpoints.map(e => e.url),
          requestTimes: results
        };
      } catch (error) {
        this.logger.error(`Network benchmark error: ${error.message}`);
        return { failed: true, error: error.message };
      }
    });
  }

  /**
   * Run all available benchmarks
   */
  async runAllBenchmarks() {
    this.logger.info('Running all benchmarks...');

    if (!await this.initialize()) {
      return false;
    }

    // Store benchmark start time
    const startTime = Date.now();

    // Run system benchmarks
    this.results.system = await this.benchmarkSystemResources();

    // Run Podman benchmarks if not explicitly disabled
    if (!this.isProduction || !benchmarkConfig.disableInProduction.includes('podmanStartup')) {
      this.results.podman = await this.benchmarkPodmanStartup();
    }

    // Run image processing benchmarks
    this.results.imageProcessing = await this.benchmarkImageProcessing();

    // Run database benchmarks
    this.results.database = await this.benchmarkDatabaseOperations();

    // Run network benchmarks
    this.results.network = await this.benchmarkNetworkOperations();

    // Calculate total duration
    const duration = Date.now() - startTime;

    // Generate summary report
    this.logger.info('\n==================================');
    this.logger.info('BENCHMARK SUMMARY REPORT');
    this.logger.info('==================================');
    this.logger.info(`Total benchmark duration: ${duration}ms`);
    this.logger.info(`System: ${this.results.system.cpuOperations} CPU operations in 1s`);

    if (this.results.podman && !this.results.podman.skipped) {
      this.logger.info(`Podman: Container startup time: ${this.results.podman.startupTime?.toFixed(2)}ms`);
    }

    if (this.results.imageProcessing && !this.results.imageProcessing.skipped) {
      this.logger.info(`Image: Resize time: ${this.results.imageProcessing.resizeTime?.toFixed(2)}ms`);
    }

    if (this.results.database && !this.results.database.failed) {
      this.logger.info(`Database: ${this.results.database.operationsPerSecond} simulated operations/sec`);
    }

    this.logger.info('==================================\n');

    // Save overall results
    if (this.options.saveResults) {
      try {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const resultsFile = path.join(this.options.resultsDir, `overall-results-${timestamp}.json`);

        await fs.writeFile(resultsFile, JSON.stringify({
          timestamp: new Date().toISOString(),
          duration,
          results: this.results,
          system: {
            platform: os.platform(),
            release: os.release(),
            cpus: os.cpus().length,
            totalMemory: os.totalmem(),
            freeMemory: os.freemem()
          },
          environment: this.environment
        }, null, 2), 'utf8');

        this.logger.info(`Overall benchmark results saved to: ${resultsFile}`);
      } catch (error) {
        this.logger.error(`Failed to save overall results: ${error.message}`);
      }
    }

    return true;
  }

  /**
   * Run specific benchmark by name
   * @param {string} benchmarkName - Name of benchmark to run
   */
  async runBenchmark(benchmarkName) {
    if (!await this.initialize()) {
      return false;
    }

    switch (benchmarkName) {
      case 'system':
        this.results.system = await this.benchmarkSystemResources();
        break;
      case 'podman':
        this.results.podman = await this.benchmarkPodmanStartup();
        break;
      case 'image':
        this.results.imageProcessing = await this.benchmarkImageProcessing();
        break;
      case 'database':
        this.results.database = await this.benchmarkDatabaseOperations();
        break;
      case 'network':
        this.results.network = await this.benchmarkNetworkOperations();
        break;
      default:
        this.logger.error(`Unknown benchmark: ${benchmarkName}`);
        return false;
    }

    return true;
  }
}

// Export the class for use in other modules
module.exports = BenchmarkRunner;

// If run directly, execute all benchmarks
if (require.main === module) {
  const args = process.argv.slice(2);
  const runner = new BenchmarkRunner();

  if (args.length > 0) {
    // Run specific benchmark
    runner.runBenchmark(args[0])
      .then(success => {
        if (!success) {
          process.exit(1);
        }
      })
      .catch(error => {
        console.error('Benchmark failed:', error);
        process.exit(1);
      });
  } else {
    // Run all benchmarks
    runner.runAllBenchmarks()
      .then(success => {
        if (!success) {
          process.exit(1);
        }
      })
      .catch(error => {
        console.error('Benchmarks failed:', error);
        process.exit(1);
      });
  }
}
