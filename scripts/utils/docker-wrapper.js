/**
 * Docker Command Wrapper Utility
 * Safely executes Docker commands and handles results
 */
const { spawn, execSync } = require('child_process');
const logger = require('./logger');

class DockerWrapper {
  constructor() {
    this.logger = logger.getLogger('docker-wrapper');
  }

  /**
   * Check if Docker is available
   * @returns {boolean} True if Docker is available
   */
  isDockerAvailable() {
    try {
      execSync('docker --version', { stdio: 'pipe' });
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Execute a Docker command synchronously
   * @param {string[]} args - Docker command arguments
   * @returns {string} Command output
   */
  executeSync(args) {
    try {
      this.logger.debug(`Running Docker command: docker ${args.join(' ')}`);
      return execSync(`docker ${args.join(' ')}`, {
        encoding: 'utf8',
        stdio: 'pipe'
      });
    } catch (error) {
      this.logger.error(`Docker command failed: ${error.message}`);
      throw error;
    }
  }

  /**
   * Execute a Docker command asynchronously
   * @param {string[]} args - Docker command arguments
   * @param {Object} options - Command options
   * @returns {Promise<Object>} Command result
   */
  execute(args, options = {}) {
    return new Promise((resolve, reject) => {
      this.logger.debug(`Running Docker command: docker ${args.join(' ')}`);

      const dockerProcess = spawn('docker', args, {
        stdio: options.stdio || 'pipe',
        ...options
      });

      let stdout = '';
      let stderr = '';

      if (dockerProcess.stdout) {
        dockerProcess.stdout.on('data', (data) => {
          const output = data.toString();
          stdout += output;

          if (options.logOutput) {
            process.stdout.write(output);
          }
        });
      }

      if (dockerProcess.stderr) {
        dockerProcess.stderr.on('data', (data) => {
          const output = data.toString();
          stderr += output;

          if (options.logOutput) {
            process.stderr.write(output);
          }
        });
      }

      dockerProcess.on('close', (code) => {
        if (code === 0) {
          resolve({ stdout, stderr, code });
        } else {
          const error = new Error(`Docker command failed with code ${code}`);
          error.code = code;
          error.stdout = stdout;
          error.stderr = stderr;
          reject(error);
        }
      });

      dockerProcess.on('error', (error) => {
        this.logger.error(`Failed to execute Docker command: ${error.message}`);
        reject(error);
      });
    });
  }

  /**
   * Run a Docker build command
   * @param {string} tag - Image tag
   * @param {string} dockerfile - Path to Dockerfile
   * @param {string} context - Build context
   * @param {Object} options - Additional options
   * @returns {Promise<Object>} Build result
   */
  async build(tag, dockerfile = './Dockerfile', context = '.', options = {}) {
    const args = ['build'];

    if (tag) {
      args.push('-t', tag);
    }

    args.push('-f', dockerfile);

    if (options.noCache) {
      args.push('--no-cache');
    }

    if (options.buildArgs) {
      for (const [key, value] of Object.entries(options.buildArgs)) {
        args.push('--build-arg', `${key}=${value}`);
      }
    }

    args.push(context);

    return this.execute(args, { logOutput: true });
  }

  /**
   * Run Docker Compose command
   * @param {string} action - Action (up, down, logs, etc.)
   * @param {string} composeFile - Path to compose file
   * @param {string} envFile - Path to env file
   * @param {string[]} additionalArgs - Additional arguments
   * @returns {Promise<Object>} Command result
   */
  async compose(action, composeFile, envFile, additionalArgs = []) {
    const args = ['compose'];

    if (composeFile) {
      args.push('-f', composeFile);
    }

    if (envFile) {
      args.push('--env-file', envFile);
    }

    args.push(action, ...additionalArgs);

    return this.execute(args, { logOutput: true });
  }
}

module.exports = new DockerWrapper();
