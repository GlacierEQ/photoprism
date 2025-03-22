#!/usr/bin/env node

/**
 * PhotoPrism CLI
 * Command-line interface for managing the PhotoPrism application
 */
const { program } = require('commander');
// Fix import path - make sure utils folder exists
const logger = require('./utils/logger');
const ContainerManager = require('./utils/container-manager');
const DeploymentManager = require('./deploy');
const ProjectInitializer = require('./initialize');
// Check if this file exists, or fix path
const PodmanTroubleshooter = require('./podman-troubleshoot');
const BenchmarkRunner = require('./benchmark-runner');
const packageJson = require('../package.json');

// Initialize logger here to avoid undefined error if module import fails
const cliLogger = logger.getLogger('cli');

// Initialize the CLI
program
  .name('photoprism-cli')
  .description('CLI for managing PhotoPrism')
  .version(packageJson.version);

// Create managers
const containerManager = new ContainerManager();
const deploymentManager = new DeploymentManager();
const initializer = new ProjectInitializer();
const troubleshooter = new PodmanTroubleshooter();
const benchmarkRunner = new BenchmarkRunner();

// Initialize command
program
  .command('init')
  .description('Initialize the PhotoPrism application')
  .option('--force', 'Force reinitialization even if already initialized')
  .option('--skip-deps', 'Skip dependency verification')
  .action(async (options) => {
    try {
      const result = await initializer.initialize({
        forceReinitialize: options.force,
        skipDependencyCheck: options.skipDeps
      });

      if (!result) {
        process.exit(1);
      }
    } catch (error) {
      cliLogger.error(`Initialization failed: ${error.message}`);
      process.exit(1);
    }
  });

// Deploy command
program
  .command('deploy')
  .description('Deploy PhotoPrism with Podman')
  .action(async () => {
    try {
      const result = await deploymentManager.deploy();
      if (!result) {
        process.exit(1);
      }
    } catch (error) {
      cliLogger.error(`Deployment failed: ${error.message}`);
      process.exit(1);
    }
  });

// Container management commands
program
  .command('up')
  .description('Start containers')
  .option('-f, --foreground', 'Run in foreground (not detached)')
  .action(async (options) => {
    try {
      const result = await containerManager.startContainers({ detached: !options.foreground });
      if (!result) process.exit(1);
    } catch (error) {
      cliLogger.error(`Failed to start containers: ${error.message}`);
      process.exit(1);
    }
  });

program
  .command('down')
  .description('Stop containers')
  .action(async () => {
    try {
      const result = await containerManager.stopContainers();
      if (!result) process.exit(1);
    } catch (error) {
      cliLogger.error(`Failed to stop containers: ${error.message}`);
      process.exit(1);
    }
  });

program
  .command('restart')
  .description('Restart containers')
  .action(async () => {
    try {
      const result = await containerManager.restartContainers();
      if (!result) process.exit(1);
    } catch (error) {
      cliLogger.error(`Failed to restart containers: ${error.message}`);
      process.exit(1);
    }
  });

program
  .command('logs')
  .description('Show container logs')
  .option('-f, --follow', 'Follow log output')
  .option('-n, --tail <lines>', 'Number of lines to show', 'all')
  .argument('[service]', 'Service name (optional)')
  .action(async (service, options) => {
    try {
      await containerManager.getLogs(service, {
        follow: options.follow,
        tail: options.tail
      });
    } catch (error) {
      cliLogger.error(`Failed to show logs: ${error.message}`);
      process.exit(1);
    }
  });

program
  .command('exec')
  .description('Execute command in service container')
  .argument('<service>', 'Service name')
  .argument('<command>', 'Command to execute')
  .action(async (service, command) => {
    try {
      const result = await containerManager.execCommand(service, command);
      if (!result) process.exit(1);
    } catch (error) {
      cliLogger.error(`Command execution failed: ${error.message}`);
      process.exit(1);
    }
  });

program
  .command('status')
  .description('Check container status')
  .action(async () => {
    try {
      const status = await containerManager.getStatus();
      if (status.success) {
        console.log(status.output);
      } else {
        cliLogger.error('Failed to get status');
        process.exit(1);
      }
    } catch (error) {
      cliLogger.error(`Failed to check status: ${error.message}`);
      process.exit(1);
    }
  });

// Troubleshooting command
program
  .command('troubleshoot')
  .description('Troubleshoot Podman issues')
  .action(async () => {
    try {
      const result = await troubleshooter.diagnose();
      if (!result.success) {
        cliLogger.warn(`Troubleshooting result: ${result.reason}`);
        process.exit(1);
      }
    } catch (error) {
      cliLogger.error(`Troubleshooting failed: ${error.message}`);
      process.exit(1);
    }
  });

// Benchmark commands
program
  .command('benchmark [type]')
  .description('Run performance benchmarks')
  .action(async (type) => {
    try {
      let result;
      if (type) {
        result = await benchmarkRunner.runBenchmark(type);
      } else {
        result = await benchmarkRunner.runAllBenchmarks();
      }

      if (!result) {
        process.exit(1);
      }
    } catch (error) {
      cliLogger.error(`Benchmark failed: ${error.message}`);
      process.exit(1);
    }
  });

// Parse arguments
program.parse(process.argv);
