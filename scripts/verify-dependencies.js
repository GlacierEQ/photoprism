const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const logger = require('./utils/logger');

/**
 * Dependency verification module
 * Checks if all required dependencies are installed
 */
class DependencyVerifier {
  constructor(configPath = '../config/dependencies.json') {
    try {
      const resolvedPath = path.resolve(__dirname, configPath);
      if (!fs.existsSync(resolvedPath)) {
        throw new Error(`Configuration file not found at ${resolvedPath}`);
      }

      this.config = require(configPath);
      this.validateConfig();

      this.missingDeps = [];
      this.logger = logger.getLogger('dependency-verifier');
      this.isWindows = os.platform() === 'win32';
      this.isMac = os.platform() === 'darwin';
      this.isLinux = os.platform() === 'linux';
    } catch (error) {
      console.error(`Failed to load configuration: ${error.message}`);
      process.exit(1);
    }
  }

  /**
   * Validate configuration format
   */
  validateConfig() {
    if (!this.config.npmDependencies || !Array.isArray(this.config.npmDependencies)) {
      throw new Error('Configuration error: npmDependencies must be an array');
    }

    if (!this.config.systemDependencies || !Array.isArray(this.config.systemDependencies)) {
      throw new Error('Configuration error: systemDependencies must be an array');
    }
  }

  /**
   * Verify npm dependencies
   * @returns {Promise<boolean>} Success status
   */
  async verifyNpmDependencies() {
    this.logger.info('Verifying npm dependencies...');

    try {
      const packageJsonPath = path.resolve(__dirname, '../package.json');

      if (!fs.existsSync(packageJsonPath)) {
        this.logger.error('package.json not found');
        return false;
      }

      const packageJson = require(packageJsonPath);
      const dependencies = { ...packageJson.dependencies || {}, ...packageJson.devDependencies || {} };

      let missingCount = 0;
      for (const dep of this.config.npmDependencies) {
        if (!dependencies[dep]) {
          this.missingDeps.push({ type: 'npm', name: dep });
          missingCount++;
        }
      }

      if (missingCount === 0) {
        this.logger.info('All npm dependencies are satisfied');
      } else {
        this.logger.warn(`Missing ${missingCount} npm dependencies`);
      }
    } catch (error) {
      this.logger.error(`Error verifying npm dependencies: ${error.message}`);
      return false;
    }

    return true;
  }

  /**
   * Check if command exists in a cross-platform way
   * @param {string} command - Command to check
   * @returns {boolean} - Whether command exists
   */
  commandExists(command) {
    try {
      const cmdCheck = this.isWindows
        ? `where ${command}`
        : `which ${command}`;

      execSync(cmdCheck, { stdio: 'ignore' });
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Verify system dependencies
   * @returns {Promise<boolean>} Success status
   */
  async verifySystemDependencies() {
    this.logger.info('Verifying system dependencies...');

    try {
      let missingCount = 0;
      for (const dep of this.config.systemDependencies) {
        if (!this.commandExists(dep)) {
          this.missingDeps.push({ type: 'system', name: dep });
          missingCount++;
        }
      }

      if (missingCount === 0) {
        this.logger.info('All system dependencies are satisfied');
      } else {
        this.logger.warn(`Missing ${missingCount} system dependencies`);
      }
    } catch (error) {
      this.logger.error(`Error verifying system dependencies: ${error.message}`);
      return false;
    }

    return true;
  }

  /**
   * Get installation instructions for missing dependencies
   * @returns {Object} Installation instructions for different platforms
   */
  getInstallationInstructions() {
    const instructions = {
      npm: {},
      system: {
        windows: {},
        mac: {},
        linux: {}
      }
    };

    // Define npm installation method
    const npmInstall = (dep) => `npm install ${dep}`;

    // Define system installation methods per OS
    const systemInstall = {
      windows: {
        node: 'Download from https://nodejs.org/',
        npm: 'Comes with Node.js installation',
        git: 'Download from https://git-scm.com/download/win',
        docker: 'Download Docker Desktop from https://www.docker.com/products/docker-desktop',
        podman: 'Download from https://github.com/containers/podman/releases',
        'podman-compose': 'Install with: pip install podman-compose'
      },
      mac: {
        node: 'brew install node',
        npm: 'Comes with Node.js installation',
        git: 'brew install git',
        docker: 'brew install --cask docker',
        podman: 'brew install podman',
        'podman-compose': 'pip install podman-compose'
      },
      linux: {
        node: 'sudo apt install nodejs (Ubuntu/Debian) or sudo dnf install nodejs (Fedora)',
        npm: 'sudo apt install npm (Ubuntu/Debian) or sudo dnf install npm (Fedora)',
        git: 'sudo apt install git (Ubuntu/Debian) or sudo dnf install git (Fedora)',
        docker: 'sudo apt install docker.io (Ubuntu/Debian) or sudo dnf install docker (Fedora)',
        podman: 'sudo apt install podman (Ubuntu/Debian) or sudo dnf install podman (Fedora)',
        'podman-compose': 'pip3 install podman-compose'
      }
    };

    // Generate instructions for missing dependencies
    for (const dep of this.missingDeps) {
      if (dep.type === 'npm') {
        instructions.npm[dep.name] = npmInstall(dep.name);
      } else if (dep.type === 'system') {
        instructions.system.windows[dep.name] = systemInstall.windows[dep.name] || `Please install ${dep.name} manually`;
        instructions.system.mac[dep.name] = systemInstall.mac[dep.name] || `Please install ${dep.name} manually`;
        instructions.system.linux[dep.name] = systemInstall.linux[dep.name] || `Please install ${dep.name} manually`;
      }
    }

    return instructions;
  }

  /**
   * Run all verifications
   * @returns {Promise<boolean>} Success status
   */
  async verifyAll() {
    this.logger.info('Starting dependency verification...');
    const startTime = process.hrtime();

    // Run verifications concurrently
    const [npmResult, systemResult] = await Promise.all([
      this.verifyNpmDependencies(),
      this.verifySystemDependencies(),
    ]);

    const [seconds, nanoseconds] = process.hrtime(startTime);
    const duration = seconds + nanoseconds / 1e9;
    this.logger.debug(`Verification completed in ${duration.toFixed(2)} seconds`);

    if (this.missingDeps.length > 0) {
      this.logger.warn('Missing dependencies:');
      this.missingDeps.forEach(dep => {
        this.logger.warn(`- ${dep.type}: ${dep.name}`);
      });

      // Show installation instructions
      const instructions = this.getInstallationInstructions();
      this.logger.info('\nInstallation instructions:');

      // Show npm instructions
      const npmDeps = this.missingDeps.filter(d => d.type === 'npm');
      if (npmDeps.length > 0) {
        this.logger.info('\nNPM dependencies:');
        npmDeps.forEach(dep => {
          this.logger.info(`  ${dep.name}: ${instructions.npm[dep.name]}`);
        });
      }

      // Show system instructions for current platform
      const systemDeps = this.missingDeps.filter(d => d.type === 'system');
      if (systemDeps.length > 0) {
        this.logger.info('\nSystem dependencies:');
        const platform = this.isWindows ? 'windows' : (this.isMac ? 'mac' : 'linux');
        systemDeps.forEach(dep => {
          this.logger.info(`  ${dep.name}: ${instructions.system[platform][dep.name]}`);
        });
      }

      return false;
    }

    this.logger.info('All dependencies verified successfully');
    return npmResult && systemResult;
  }
}

// Export the class for use in other modules
module.exports = DependencyVerifier;

// If run directly, execute verification
if (require.main === module) {
  const verifier = new DependencyVerifier();
  verifier.verifyAll()
    .then(success => {
      if (!success) {
        process.exit(1);
      }
    })
    .catch(error => {
      console.error('Verification failed:', error);
      process.exit(1);
    });
}
