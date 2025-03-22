/**
 * Container Management Utility
 * Provides a unified interface for managing Podman containers
 */
const { execSync } = require('child_process');
const fs = require('fs').promises;
const path = require('path');
const logger = require('./logger');

class ContainerManager {
  constructor(options = {}) {
    this.logger = logger.getLogger('container-manager');
    this.options = {
      composeFile: process.env.COMPOSE_FILE || 'podman/podman-compose.prod.yml',
      envFile: process.env.ENV_FILE || 'podman/.env.prod',
      projectName: process.env.PROJECT_NAME || 'photoprism',
      rootDir: path.resolve(__dirname, '../..'),
      ...options
    };

    // Ensure file paths are absolute
    if (!path.isAbsolute(this.options.composeFile)) {
      this.options.composeFile = path.join(this.options.rootDir, this.options.composeFile);
    }

    if (!path.isAbsolute(this.options.envFile)) {
      this.options.envFile = path.join(this.options.rootDir, this.options.envFile);
    }
  }

  /**
   * Get the command for podman-compose with proper arguments
   */
  getComposeCommand() {
    return `podman-compose -f "${this.options.composeFile}" --env-file "${this.options.envFile}"`;
  }

  /**
   * Start containers
   * @param {Object} options - Start options
   * @param {boolean} options.detached - Run containers in detached mode
   */
  async startContainers(options = { detached: true }) {
    try {
      const cmd = `${this.getComposeCommand()} up${options.detached ? ' -d' : ''}`;
      this.logger.info(`Starting containers with command: ${cmd}`);

      execSync(cmd, {
        cwd: this.options.rootDir,
        stdio: 'inherit'
      });

      this.logger.info('Containers started successfully');
      return true;
    } catch (error) {
      this.logger.error(`Failed to start containers: ${error.message}`);
      return false;
    }
  }

  /**
   * Stop containers
   */
  async stopContainers() {
    try {
      const cmd = `${this.getComposeCommand()} down`;
      this.logger.info(`Stopping containers with command: ${cmd}`);

      execSync(cmd, {
        cwd: this.options.rootDir,
        stdio: 'inherit'
      });

      this.logger.info('Containers stopped successfully');
      return true;
    } catch (error) {
      this.logger.error(`Failed to stop containers: ${error.message}`);
      return false;
    }
  }

  /**
   * Restart containers
   */
  async restartContainers() {
    try {
      const cmd = `${this.getComposeCommand()} restart`;
      this.logger.info(`Restarting containers with command: ${cmd}`);

      execSync(cmd, {
        cwd: this.options.rootDir,
        stdio: 'inherit'
      });

      this.logger.info('Containers restarted successfully');
      return true;
    } catch (error) {
      this.logger.error(`Failed to restart containers: ${error.message}`);
      return false;
    }
  }

  /**
   * Get container logs
   * @param {string} service - Service name (optional, if not provided, gets logs for all services)
   * @param {Object} options - Log options
   * @param {boolean} options.follow - Follow log output
   * @param {number} options.tail - Number of lines to show
   */
  async getLogs(service = '', options = { follow: false, tail: 'all' }) {
    try {
      let cmd = `${this.getComposeCommand()} logs`;

      if (options.follow) {
        cmd += ' -f';
      }

      if (options.tail !== 'all') {
        cmd += ` --tail=${options.tail}`;
      }

      if (service) {
        cmd += ` ${service}`;
      }

      this.logger.info(`Getting logs with command: ${cmd}`);

      execSync(cmd, {
        cwd: this.options.rootDir,
        stdio: 'inherit'
      });

      return true;
    } catch (error) {
      this.logger.error(`Failed to get logs: ${error.message}`);
      return false;
    }
  }

  /**
   * Execute command in a container
   * @param {string} service - Service name
   * @param {string} command - Command to execute
   */
  async execCommand(service, command) {
    if (!service || !command) {
      this.logger.error('Service name and command are required');
      return false;
    }

    try {
      const cmd = `${this.getComposeCommand()} exec ${service} ${command}`;
      this.logger.info(`Executing command: ${cmd}`);

      execSync(cmd, {
        cwd: this.options.rootDir,
        stdio: 'inherit'
      });

      return true;
    } catch (error) {
      this.logger.error(`Command execution failed: ${error.message}`);
      return false;
    }
  }

  /**
   * Get container status
   */
  async getStatus() {
    try {
      const cmd = `${this.getComposeCommand()} ps`;
      this.logger.debug(`Getting status with command: ${cmd}`);

      const output = execSync(cmd, {
        cwd: this.options.rootDir,
        encoding: 'utf8'
      });

      return {
        success: true,
        output: output.trim(),
        isRunning: !output.includes('Exit') && output.includes('Up')
      };
    } catch (error) {
      this.logger.error(`Failed to get container status: ${error.message}`);
      return {
        success: false,
        output: error.message,
        isRunning: false
      };
    }
  }
}

module.exports = ContainerManager;
