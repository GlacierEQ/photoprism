const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const readline = require('readline');
const logger = require('./utils/logger');

/**
 * Docker troubleshooting utility
 * Helps diagnose and fix common Docker issues
 */
class DockerTroubleshooter {
  constructor() {
    this.logger = logger.getLogger('docker-troubleshoot');
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
   * Check if Docker is installed
   */
  async checkDockerInstalled() {
    try {
      execSync('docker --version', { stdio: 'pipe' });
      this.logger.info('✅ Docker is installed');
      return true;
    } catch (error) {
      this.logger.error('❌ Docker is not installed or not in PATH');
      return false;
    }
  }

  /**
   * Check if Docker Compose is installed
   */
  async checkDockerComposeInstalled() {
    try {
      // Try docker-compose command first
      try {
        execSync('docker-compose --version', { stdio: 'pipe' });
        this.logger.info('✅ Docker Compose is installed (standalone)');
        return true;
      } catch {
        // Try docker compose command (Docker Compose V2)
        execSync('docker compose version', { stdio: 'pipe' });
        this.logger.info('✅ Docker Compose V2 is installed (plugin)');
        return true;
      }
    } catch (error) {
      this.logger.error('❌ Docker Compose is not installed or not in PATH');
      return false;
    }
  }

  /**
   * Check if Docker daemon is running
   */
  async checkDockerRunning() {
    try {
      execSync('docker info', { stdio: 'pipe' });
      this.logger.info('✅ Docker daemon is running');
      return true;
    } catch (error) {
      this.logger.error('❌ Docker daemon is not running');
      return false;
    }
  }

  /**
   * Check Docker Desktop status (Windows/Mac)
   */
  async checkDockerDesktop() {
    if (!this.isWindows && !this.isMac) {
      this.logger.info('ℹ️ Docker Desktop check skipped (not Windows/Mac)');
      return null;
    }

    let dockerDesktopPath;
    let processName;

    if (this.isWindows) {
      dockerDesktopPath = path.join(os.homedir(), 'AppData', 'Local', 'Docker', 'Docker');
      processName = 'Docker Desktop.exe';
    } else if (this.isMac) {
      dockerDesktopPath = '/Applications/Docker.app';
      processName = 'Docker';
    }

    // Check if Docker Desktop is installed
    const isInstalled = fs.existsSync(dockerDesktopPath);
    if (!isInstalled) {
      this.logger.warn('⚠️ Docker Desktop installation not found at expected location');
      return false;
    }

    // Check if Docker Desktop process is running
    try {
      if (this.isWindows) {
        execSync('tasklist /FI "IMAGENAME eq ' + processName + '"', { stdio: 'pipe' });
        if (execSync('tasklist /FI "IMAGENAME eq ' + processName + '"', { encoding: 'utf8' }).includes(processName)) {
          this.logger.info('✅ Docker Desktop is running');
          return true;
        }
      } else {
        if (execSync('pgrep -f "Docker"', { encoding: 'utf8' }).trim()) {
          this.logger.info('✅ Docker Desktop is running');
          return true;
        }
      }

      this.logger.warn('⚠️ Docker Desktop is installed but not running');
      return false;
    } catch (error) {
      this.logger.warn('⚠️ Unable to determine Docker Desktop running status');
      return null;
    }
  }

  /**
   * Suggest Docker Desktop startup (Windows)
   */
  async startDockerDesktop() {
    if (this.isWindows) {
      try {
        this.logger.info('Attempting to start Docker Desktop...');
        const dockerPath = path.join(os.homedir(), 'AppData', 'Local', 'Docker', 'Docker', 'Docker Desktop.exe');

        if (fs.existsSync(dockerPath)) {
          spawn(dockerPath, [], {
            detached: true,
            stdio: 'ignore'
          }).unref();

          this.logger.info('Docker Desktop launch initiated. Please wait for it to start...');
          this.logger.info('You may need to accept the Windows UAC prompt if it appears');
          return true;
        } else {
          this.logger.warn('Docker Desktop executable not found at expected location');
          return false;
        }
      } catch (error) {
        this.logger.error(`Failed to start Docker Desktop: ${error.message}`);
        return false;
      }
    } else if (this.isMac) {
      this.logger.info('On macOS, please start Docker Desktop from the Applications folder');
      return false;
    } else {
      this.logger.info('On Linux, please start Docker with: sudo systemctl start docker');
      return false;
    }
  }

  /**
   * Provide installation instructions based on platform
   */
  showInstallationInstructions() {
    this.logger.info('\n📋 Docker Installation Instructions:');

    if (this.isWindows) {
      this.logger.info('1. Download Docker Desktop from: https://www.docker.com/products/docker-desktop');
      this.logger.info('2. Run the installer and follow the prompts');
      this.logger.info('3. Restart your computer after installation');
      this.logger.info('4. Start Docker Desktop from the Start menu');
    } else if (this.isMac) {
      this.logger.info('1. Download Docker Desktop from: https://www.docker.com/products/docker-desktop');
      this.logger.info('2. Drag the Docker app to your Applications folder');
      this.logger.info('3. Start Docker Desktop from the Applications folder');
    } else {
      this.logger.info('1. Install Docker using your package manager:');
      this.logger.info('   sudo apt update && sudo apt install docker.io docker-compose -y  # For Ubuntu/Debian');
      this.logger.info('   sudo dnf install docker docker-compose -y  # For Fedora/RHEL');
      this.logger.info('2. Start the Docker service:');
      this.logger.info('   sudo systemctl enable docker');
      this.logger.info('   sudo systemctl start docker');
      this.logger.info('3. Add your user to the docker group:');
      this.logger.info('   sudo usermod -aG docker $USER');
      this.logger.info('4. Log out and back in for group changes to take effect');
    }
  }

  /**
   * Run all checks and provide guidance
   */
  async diagnose() {
    this.logger.info('Starting Docker troubleshooting...');

    // Check if Docker is installed
    const dockerInstalled = await this.checkDockerInstalled();

    if (!dockerInstalled) {
      this.showInstallationInstructions();
      return {
        success: false,
        reason: 'docker-not-installed',
        fixApplied: false
      };
    }

    // Check Docker Compose
    await this.checkDockerComposeInstalled();

    // Check Docker Desktop if on Windows/Mac
    if (this.isWindows || this.isMac) {
      const dockerDesktopRunning = await this.checkDockerDesktop();

      if (dockerDesktopRunning === false) {
        const rl = this.createInterface();

        const answer = await new Promise(resolve => {
          rl.question('Would you like to attempt to start Docker Desktop now? (y/n): ', resolve);
        });

        rl.close();

        if (answer.toLowerCase() === 'y') {
          const started = await this.startDockerDesktop();

          if (started) {
            this.logger.info('Please wait approximately 30 seconds for Docker Desktop to fully start.');
            this.logger.info('After Docker Desktop is running, run the deployment command again.');
            return {
              success: false,
              reason: 'docker-starting',
              fixApplied: true
            };
          }
        }
      }
    }

    // Final check if Docker daemon is running
    const dockerRunning = await this.checkDockerRunning();

    if (!dockerRunning) {
      if (this.isLinux) {
        this.logger.info('On Linux, you can start Docker with:');
        this.logger.info('sudo systemctl start docker');
      } else {
        this.logger.info('Please ensure Docker Desktop is running before continuing.');
      }

      return {
        success: false,
        reason: 'docker-not-running',
        fixApplied: false
      };
    }

    this.logger.info('Docker appears to be properly installed and running! 🎉');
    return {
      success: true,
      reason: null,
      fixApplied: false
    };
  }
}

// Export the class for use in other modules
module.exports = DockerTroubleshooter;

// If run directly, execute troubleshooting
if (require.main === module) {
  const troubleshooter = new DockerTroubleshooter();
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
