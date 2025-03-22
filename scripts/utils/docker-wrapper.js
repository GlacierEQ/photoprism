const { spawn, execSync } = require('child_process');
const fs = require('fs').promises;
const path = require('path');
const logger = require('./logger');

class DockerWrapper {
  constructor() {
    this.logger = logger.getLogger('docker-wrapper');
    this.requiredEnvVars = [
      'PHOTOPRISM_SITE_URL',
      'PHOTOPRISM_ADMIN_PASSWORD',
      'MYSQL_PASSWORD',
      'MYSQL_ROOT_PASSWORD',
      'PHOTOPRISM_SITE_TITLE',
      'BRAINS_SERVER_KEY'
    ];
  }

  log(message) {
    this.logger.debug(message);
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
   * Verify required environment variables exist in env file
   * @param {string} envFile - Path to env file
   * @returns {Promise<{missing: string[], hasErrors: boolean}>}
   */
  async verifyEnvironment(envFile) {
    try {
      const content = await fs.readFile(envFile, 'utf8');
      const envVars = {};
      const missing = [];

      // Parse env file content
      content.split('\n').forEach(line => {
        const match = line.match(/^\s*([\w.-]+)\s*=\s*(.*)?\s*$/);
        if (match) {
          envVars[match[1]] = match[2] || '';
        }
      });

    } catch (error) {
      this.logger.error(`Failed to verify environment: ${error.message}`);
      throw error;
    }
  }

  /**
   * Run Docker Compose command with environment validation
   * @param {string} action - Action (up, down, logs, etc.)
   * @param {string} composeFile - Path to compose file
   * @param {string} envFile - Path to env file
   * @param {string[]} additionalArgs - Additional arguments
   * @returns {Promise<Object>} Command result
   */
  async composeWithEnv(action, composeFile, envFile, additionalArgs = []) {
    try {
      // Verify files exist
      await fs.access(composeFile);
      await fs.access(envFile);

      // Verify environment first
      const envCheck = await this.verifyEnvironment(envFile);
      if (envCheck.hasErrors) {
        this.logger.warn('Missing required environment variables:');
        envCheck.missing.forEach(varName => {
          this.logger.warn(`  - ${varName}`);
        });
      }

      // Update compose file to remove version if present
      const composeContent = await fs.readFile(composeFile, 'utf8');
      if (composeContent.includes('version:')) {
        const updatedContent = composeContent.replace(/version:.*\n/, '');
        await fs.writeFile(composeFile, updatedContent);
        this.logger.info('Removed obsolete version attribute from compose file');
      }

      return this.compose(action, composeFile, envFile, additionalArgs);
    } catch (error) {
      if (error.code === 'ENOENT') {
        this.logger.error(`File not found: ${error.path}`);
        throw new Error(`Required file not found: ${error.path}`);
      }
      throw error;
    }
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
