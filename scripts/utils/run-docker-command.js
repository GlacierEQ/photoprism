/**
 * Docker Command Runner
 * Script to run Docker commands safely without PowerShell parsing issues
 */
const path = require('path');
const dockerWrapper = require('./docker-wrapper');
const logger = require('./logger').getLogger('docker-command');

async function main() {
  // Check arguments
  const args = process.argv.slice(2);
  const command = args[0];

  if (!command) {
    logger.error('No command specified. Please provide a valid Docker command to execute.');

    console.log('Usage: node run-docker-command.js <command> [options]');
    console.log('Commands: build, up, down, logs, restart');
    process.exit(1);
  }

  // Check if Docker is available
  if (!dockerWrapper.isDockerAvailable()) {
    logger.error('Docker is not available. Please ensure Docker is installed and accessible from your command line.');

    process.exit(1);
  }

  // Define paths
  const rootDir = path.resolve(__dirname, '../..');
  const composeFile = path.join(rootDir, 'docker', 'docker-compose.prod.yml');
  const envFile = path.join(rootDir, 'docker', '.env.prod');

  try {
    switch (command) {
      case 'build':
        logger.info('Building Docker image...');
        await dockerWrapper.build('photoprism2', path.join(rootDir, 'Dockerfile'), rootDir);
        logger.info('Docker build completed');
        break;

      case 'up':
        logger.info('Starting Docker containers...');
        await dockerWrapper.compose('up', composeFile, envFile, ['-d']);
        logger.info('Docker containers started');
        break;

      case 'down':
        logger.info('Stopping Docker containers...');
        await dockerWrapper.compose('down', composeFile, envFile);
        logger.info('Docker containers stopped');
        break;

      case 'logs':
        logger.info('Showing Docker logs...');
        await dockerWrapper.compose('logs', composeFile, envFile, ['-f']);
        break;

      case 'restart':
        logger.info('Restarting Docker containers...');
        await dockerWrapper.compose('restart', composeFile, envFile);
        logger.info('Docker containers restarted');
        break;

      default:
    logger.error(`Unknown command: ${command}. Please use one of the following commands: build, up, down, logs, restart.`);

        process.exit(1);
    }
  } catch (error) {
    logger.error(`Command failed: ${error.message}. Please check the command and try again.`);

    process.exit(1);
  }
}

main().catch(error => {
  logger.error(`Unexpected error: ${error.message}`);
  process.exit(1);
});
