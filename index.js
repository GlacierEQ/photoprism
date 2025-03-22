/**
 * PhotoPrism2 Main Entry Point
 *
 * This file orchestrates the initialization, deployment and monitoring
 * of the PhotoPrism application.
 */

const path = require('path');
const fs = require('fs').promises;
const logger = require('./scripts/utils/logger').getLogger('main');
const DependencyVerifier = require('./scripts/verify-dependencies');
const ProjectInitializer = require('./scripts/initialize');
const DeploymentManager = require('./scripts/deploy');
const PerformanceBenchmark = require('./scripts/utils/performance');

/**
 * PhotoPrism Application Manager
 * Manages the lifecycle of the PhotoPrism application
 */
class PhotoPrismManager {
  constructor(options = {}) {
    this.options = {
      skipDependencies: false,
      skipBenchmarks: false,
      autoStart: false,
      ...options
    };

    // Performance benchmarking
    this.benchmark = new PerformanceBenchmark();
  }

  /**
   * Initialize the application
   */
  async initialize() {
    logger.info('Initializing PhotoPrism application...');
    this.benchmark.startTest('initialization');

    try {
      // Verify dependencies if not skipped
      if (!this.options.skipDependencies) {
        this.benchmark.mark('dependencies-check');
        const verifier = new DependencyVerifier();
        const dependenciesOk = await verifier.verifyAll();
        this.benchmark.measure('dependencies-verification', 'dependencies-check');

        if (!dependenciesOk) {
          logger.error('Dependency verification failed. Please install missing dependencies.');
          return false;
        }
      }

      // Initialize the project
      this.benchmark.mark('project-initialization');
      const initializer = new ProjectInitializer();
      const initialized = await initializer.initialize();
      this.benchmark.measure('project-initialization-time', 'project-initialization');

      if (!initialized) {
        logger.error('Project initialization failed.');
        return false;
      }

      logger.info('Initialization completed successfully.');

      // Finalize benchmark
      await this.benchmark.endTest();

      return true;
    } catch (error) {
      logger.error(`Initialization failed: ${error.message}`);
      await this.benchmark.endTest();
      return false;
    }
  }

  /**
   * Deploy PhotoPrism
   */
  async deploy() {
    logger.info('Deploying PhotoPrism with Podman...');
    this.benchmark.startTest('deployment');

    try {
      this.benchmark.mark('deployment-start');
      const deploymentManager = new DeploymentManager();
      const deployed = await deploymentManager.deploy();
      const deploymentTime = this.benchmark.measure('deployment-time', 'deployment-start');

      if (!deployed) {
        logger.error('Deployment failed.');
        await this.benchmark.endTest();
        return false;
      }

      logger.info(`Deployment completed successfully in ${deploymentTime.toFixed(2)}ms.`);

      // Finalize benchmark
      await this.benchmark.endTest();

      return true;
    } catch (error) {
      logger.error(`Podman deployment failed: ${error.message}`);
      await this.benchmark.endTest();
      return false;
    }
  }

  /**
   * Run performance benchmarks
   */
  async runBenchmarks() {
    if (this.options.skipBenchmarks) {
      logger.info('Benchmarks skipped.');
      return true;
    }

    try {
      const BenchmarkRunner = require('./scripts/benchmark-runner');
      const runner = new BenchmarkRunner();

      logger.info('Running performance benchmarks...');
      const success = await runner.runAllBenchmarks();

      if (!success) {
        logger.warn('Some benchmarks failed or were skipped.');
      } else {
        logger.info('All benchmarks completed successfully.');
      }

      return true;
    } catch (error) {
      logger.error(`Benchmark execution failed: ${error.message}`);
      return false;
    }
  }

  /**
   * Start the PhotoPrism application
   */
  async start() {
    logger.info('Starting PhotoPrism application...');

    // Initialize first
    const initialized = await this.initialize();
    if (!initialized) {
      return false;
    }

    // Deploy if auto-start is enabled
    if (this.options.autoStart) {
      const deployed = await this.deploy();
      if (!deployed) {
        return false;
      }

      // Run benchmarks after deployment
      await this.runBenchmarks();
    }

    logger.info('PhotoPrism application ready.');
    return true;
  }
}

// Export the PhotoPrism manager class
module.exports = PhotoPrismManager;

// If run directly, start the application
if (require.main === module) {
  // Parse command line arguments
  const args = process.argv.slice(2);
  const command = args[0] || 'start';

  // Create options based on arguments
  const options = {
    skipDependencies: args.includes('--skip-deps'),
    skipBenchmarks: args.includes('--skip-benchmarks'),
    autoStart: args.includes('--auto-start') || command === 'start'
  };

  // Create the application manager
  const manager = new PhotoPrismManager(options);

  // Execute requested command
  switch (command) {
    case 'start':
      manager.start()
        .then(success => {
          if (!success) {
            process.exit(1);
          }
        })
        .catch(error => {
          console.error('Application failed to start:', error);
          process.exit(1);
        });
      break;

    case 'init':
      manager.initialize()
        .then(success => {
          if (!success) {
            process.exit(1);
          }
        })
        .catch(error => {
          console.error('Initialization failed:', error);
          process.exit(1);
        });
      break;

    case 'deploy':
      manager.initialize()
        .then(initialized => {
          if (!initialized) {
            process.exit(1);
            return;
          }
          return manager.deploy();
        })
        .then(success => {
          if (!success) {
            process.exit(1);
          }
        })
        .catch(error => {
          console.error('Deployment failed:', error);
          process.exit(1);
        });
      break;

    case 'benchmark':
      manager.runBenchmarks()
        .then(success => {
          if (!success) {
            process.exit(1);
          }
        })
        .catch(error => {
          console.error('Benchmarks failed:', error);
          process.exit(1);
        });
      break;

    default:
      console.error(`Unknown command: ${command}`);
      console.log('Available commands: start, init, deploy, benchmark');
      process.exit(1);
  }
}
