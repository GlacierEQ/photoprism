const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const readline = require('readline');
const logger = require('./utils/logger');

/**
 * Podman troubleshooting utility
 * Helps diagnose and fix common Podman issues
 */
class PodmanTroubleshooter {
  constructor() {
    this.logger = logger.getLogger('podman-troubleshoot');
    this.isWindows = os.platform() === 'win32';
    this.isMac = os.platform() === 'darwin';
    this.isLinux = os.platform() === 'linux';
  }

  /**
   * Create interactive CLI
   */
  createInterface() {
    return readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });
  }

  /**
   * Check if Podman is installed
   */
  async checkPodmanInstalled() {
    try {
      execSync('podman --version', { stdio: 'pipe' });
      this.logger.info('✅ Podman is installed');
      return true;
    } catch (error) {
      this.logger.error('❌ Podman is not installed or not in PATH');
      return false;
    }
  }

  /**
   * Check if Podman Compose is installed
   */
  async checkPodmanComposeInstalled() {
    try {
      execSync('podman-compose --version', { stdio: 'pipe' });
      this.logger.info('✅ Podman Compose is installed');
      return true;
    } catch (error) {
      this.logger.error('❌ Podman Compose is not installed or not in PATH');
      return false;
    }
  }

  /**
   * Check if Podman is running properly
   */
  async checkPodmanRunning() {
    try {
      execSync('podman info', { stdio: 'pipe' });
      this.logger.info('✅ Podman is running properly');
      return true;
    } catch (error) {
      this.logger.error('❌ Podman is not running properly');
      return false;
    }
  }

  /**
   * Provide installation instructions based on platform
   */
  showInstallationInstructions() {
    this.logger.info('\n📋 Podman Installation Instructions:');

    if (this.isWindows) {
      this.logger.info('1. Install Podman for Windows:');
      this.logger.info('   - Visit https://github.com/containers/podman/releases');
      this.logger.info('   - Download the Windows installer (podman-x.y.z-setup.exe)');
      this.logger.info('   - Run the installer and follow the prompts');
      this.logger.info('2. Install Podman Compose:');
      this.logger.info('   - pip install podman-compose');
    } else if (this.isMac) {
      this.logger.info('1. Install Podman for macOS:');
      this.logger.info('   - brew install podman');
      this.logger.info('2. Install Podman Compose:');
      this.logger.info('   - pip install podman-compose');
    } else {
      this.logger.info('1. Install Podman using your package manager:');
      this.logger.info('   sudo apt install podman  # For Ubuntu/Debian');
      this.logger.info('   sudo dnf install podman  # For Fedora/RHEL');
      this.logger.info('2. Install Podman Compose:');
      this.logger.info('   pip3 install podman-compose');
    }
  }

  /**
   * Start Podman machine on Windows/Mac
   */
  async startPodmanMachine() {
    if (this.isWindows || this.isMac) {
      try {
        this.logger.info('Attempting to start Podman machine...');
        execSync('podman machine start', { stdio: 'pipe' });
        this.logger.info('Podman machine started successfully');
        return true;
      } catch (error) {
        this.logger.error(`Failed to start Podman machine: ${error.message}`);

        // Try to initialize if it doesn't exist yet
        try {
          this.logger.info('Attempting to initialize Podman machine...');
          execSync('podman machine init', { stdio: 'pipe' });
          execSync('podman machine start', { stdio: 'pipe' });
          this.logger.info('Podman machine initialized and started successfully');
          return true;
        } catch (initError) {
          this.logger.error(`Failed to initialize Podman machine: ${initError.message}`);
          return false;
        }
      }
    } else {
      this.logger.info('Podman machine is not needed on Linux');
      return true;
    }
  }

  /**
   * Run all checks and provide guidance
   */
  async diagnose() {
    this.logger.info('Starting Podman troubleshooting...');

    // Check if Podman is installed
    const podmanInstalled = await this.checkPodmanInstalled();

    if (!podmanInstalled) {
      this.showInstallationInstructions();
      return {
        success: false,
        reason: 'podman-not-installed',
        fixApplied: false
      };
    }

    // Check Podman Compose
    await this.checkPodmanComposeInstalled();

    // Check Podman machine on Windows/Mac
    if (this.isWindows || this.isMac) {
      const rl = this.createInterface();

      const answer = await new Promise(resolve => {
        rl.question('Would you like to start/initialize the Podman machine? (y/n): ', resolve);
      });

      rl.close();

      if (answer.toLowerCase() === 'y') {
        const started = await this.startPodmanMachine();

        if (started) {
          this.logger.info('Podman machine is ready.');
        } else {
          return {
            success: false,
            reason: 'podman-machine-failed',
            fixApplied: false
          };
        }
      }
    }

    // Final check if Podman is running
    const podmanRunning = await this.checkPodmanRunning();

    if (!podmanRunning) {
      this.logger.info('Please ensure Podman is properly configured before continuing.');

      return {
        success: false,
        reason: 'podman-not-running',
        fixApplied: false
      };
    }

    this.logger.info('Podman appears to be properly installed and running! 🎉');
    return {
      success: true,
      reason: null,
      fixApplied: false
    };
  }
}

// Export the class for use in other modules
module.exports = PodmanTroubleshooter;

// If run directly, execute troubleshooting
if (require.main === module) {
  const troubleshooter = new PodmanTroubleshooter();
  troubleshooter.diagnose()
    .then(result => {
      if (!result.success) {
        process.exit(1);
      }
    })
    .catch(error => {
      console.error('Troubleshooting failed:', error);
      process.exit(1);
    });
}
