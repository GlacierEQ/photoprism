const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs').promises;
const logger = require('./utils/logger');
const DependencyVerifier = require('./verify-dependencies');
const ProjectInitializer = require('./initialize');
const PodmanTroubleshooter = require('./podman-troubleshoot');

/**
 * PhotoPrism Deployment Manager
 * Manages the Podman deployment process for PhotoPrism
 */
class DeploymentManager {
  constructor() {
    this.logger = logger.getLogger('deployment');
    this.rootDir = path.resolve(__dirname, '..');
    this.podmanDir = path.join(this.rootDir, 'podman');
    this.podmanComposeFile = path.join(this.podmanDir, 'podman-compose.prod.yml');
    this.envFile = path.join(this.podmanDir, '.env.prod');
    this.troubleshooter = new PodmanTroubleshooter();
  }

  /**
   * Verify Podman is installed and running
   */
  async verifyPodman() {
    this.logger.info('Verifying Podman installation...');

    try {
      execSync('podman --version', { stdio: 'pipe' });
      execSync('podman-compose --version', { stdio: 'pipe', shell: true });

      // Check if Podman is running properly
      execSync('podman info', { stdio: 'pipe' });

      this.logger.info('Podman is installed and running');
      return true;
    } catch (error) {
      this.logger.error(`Podman verification failed: ${error.message}`);

      // Run troubleshooter to diagnose the issue
      this.logger.info('Running Podman troubleshooter...');
      const diagnosis = await this.troubleshooter.diagnose();

      if (!diagnosis.success) {
        this.logger.error('Please ensure Podman is installed and running before deploying.');
      }

      return false;
    }
  }

  /**
   * Create required directories for PhotoPrism
   */
  async createPhotoprismDirectories() {
    this.logger.info('Creating PhotoPrism directories...');

    const directories = [
      path.join(this.rootDir, 'storage'),
      path.join(this.rootDir, 'originals'),
      path.join(this.rootDir, 'import'),
      path.join(this.rootDir, 'database'),
      path.join(this.rootDir, 'backups'),
      path.join(this.rootDir, 'redis')
    ];

    for (const dir of directories) {
      try {
        await fs.access(dir);
        this.logger.debug(`Directory exists: ${dir}`);
      } catch {
        this.logger.info(`Creating directory: ${dir}`);
        await fs.mkdir(dir, { recursive: true });
      }
    }

    return true;
  }

  /**
   * Ensure Podman configuration files exist
   */
  async verifyPodmanConfig() {
    this.logger.info('Verifying Podman configuration files...');

    // Ensure podman directory exists
    try {
      await fs.access(this.podmanDir);
    } catch {
      this.logger.info('Creating Podman directory');
      await fs.mkdir(this.podmanDir, { recursive: true });
    }

    // Check for docker-compose.prod.yml in docker directory (legacy)
    const legacyDockerComposeFile = path.join(this.rootDir, 'docker', 'docker-compose.prod.yml');
    const legacyEnvFile = path.join(this.rootDir, 'docker', '.env.prod');

    // Check podman-compose.prod.yml
    try {
      await fs.access(this.podmanComposeFile);
      this.logger.info('Podman Compose file exists');
    } catch {
      // Try to migrate from Docker if available
      try {
        await fs.access(legacyDockerComposeFile);
        this.logger.info('Migrating Docker Compose file to Podman Compose');

        // Read docker-compose file
        const dockerComposeContent = await fs.readFile(legacyDockerComposeFile, 'utf8');

        // Convert to podman-compose format if needed (typically the same format)
        let podmanComposeContent = dockerComposeContent;

        // Write to podman-compose file
        await fs.writeFile(this.podmanComposeFile, podmanComposeContent);

        this.logger.info('Docker Compose file migrated to Podman Compose');
      } catch {
        this.logger.error(`Podman Compose file not found: ${this.podmanComposeFile}`);
        this.logger.error('Please create the Podman Compose file before deploying');
        return false;
      }
    }

    // Check .env.prod
    try {
      await fs.access(this.envFile);
      this.logger.info('Environment file exists');
    } catch {
      // Try to migrate from Docker if available
      try {
        await fs.access(legacyEnvFile);
        this.logger.info('Migrating Docker environment file to Podman');

        await fs.copyFile(legacyEnvFile, this.envFile);

        this.logger.info('Environment file migrated to Podman directory');
      } catch {
        this.logger.warn(`Environment file not found: ${this.envFile}`);
        this.logger.info('Creating default environment file...');

        // Create default .env.prod file from example if it exists
        const envExampleFile = path.join(this.podmanDir, '.env.example');
        try {
          await fs.access(envExampleFile);
          await fs.copyFile(envExampleFile, this.envFile);
          this.logger.info('Created environment file from example');
        } catch {
          this.logger.error('Example environment file not found');
          this.logger.error('Please create an environment file manually');
          return false;
        }
      }
    }

    return true;
  }

  /**
   * Deploy PhotoPrism using Podman Compose
   */
  async deployPhotoprism() {
    this.logger.info('Deploying PhotoPrism with Podman Compose...');

    // Use podman-compose command
    const podmanComposeCmd = 'podman-compose';

    try {
      // Pull latest images
      this.logger.info('Pulling container images...');
      execSync(`${podmanComposeCmd} -f "${this.podmanComposeFile}" --env-file "${this.envFile}" pull`, {
        cwd: this.rootDir,
        stdio: 'inherit'
      });

      // Stop any existing containers
      this.logger.info('Stopping existing containers...');
      execSync(`${podmanComposeCmd} -f "${this.podmanComposeFile}" --env-file "${this.envFile}" down`, {
        cwd: this.rootDir,
        stdio: 'inherit'
      });

      // Start containers
      this.logger.info('Starting containers...');
      execSync(`${podmanComposeCmd} -f "${this.podmanComposeFile}" --env-file "${this.envFile}" up -d`, {
        cwd: this.rootDir,
        stdio: 'inherit'
      });

      this.logger.info('PhotoPrism deployed successfully with Podman!');
      return true;
    } catch (error) {
      this.logger.error(`Deployment failed: ${error.message}`);
      return false;
    }
  }

  /**
   * Verify PhotoPrism is running properly
   */
  async verifyDeployment() {
    this.logger.info('Verifying PhotoPrism deployment...');

    const podmanComposeCmd = 'podman-compose';

    try {
      // Check if containers are running
      const result = execSync(`${podmanComposeCmd} -f "${this.podmanComposeFile}" --env-file "${this.envFile}" ps`, {
        cwd: this.rootDir,
        encoding: 'utf8'
      });

      if (result.includes('photoprism') && !result.includes('Exit')) {
        this.logger.info('PhotoPrism container is running');

        // Get the site URL from env file
        try {
          const envContent = await fs.readFile(this.envFile, 'utf8');
          const matches = envContent.match(/PHOTOPRISM_SITE_URL=(.*)/);
          const url = matches ? matches[1].replace(/["']/g, '') : 'http://localhost:2342';

          this.logger.info(`PhotoPrism is accessible at: ${url}`);
          this.logger.info('Default login credentials: admin / admin (if not changed in .env.prod)');
        } catch (err) {
          this.logger.info('PhotoPrism is likely accessible at: http://localhost:2342');
        }

        return true;
      } else {
        this.logger.error('PhotoPrism container is not running');
        this.logger.info('To troubleshoot, run: npm run podman:logs');
        return false;
      }
    } catch (error) {
      this.logger.error(`Verification failed: ${error.message}`);
      return false;
    }
  }

  /**
   * Run the full deployment process
   */
  async deploy() {
    try {
      this.logger.info('Starting PhotoPrism deployment with Podman...');

      // Initialize project first
      const initializer = new ProjectInitializer();
      const initialized = await initializer.initialize();

      if (!initialized) {
        this.logger.error('Project initialization failed');
        return false;
      }

      // Verify Podman
      if (!await this.verifyPodman()) {
        return false;
      }

      // Create directories
      if (!await this.createPhotoprismDirectories()) {
        return false;
      }

      // Verify Podman config
      if (!await this.verifyPodmanConfig()) {
        return false;
      }

      // Deploy PhotoPrism
      if (!await this.deployPhotoprism()) {
        return false;
      }

      // Verify deployment
      if (!await this.verifyDeployment()) {
        return false;
      }

      this.logger.info('Deployment with Podman completed successfully!');
      this.logger.info('For usage instructions, see USAGE-GUIDE.md');
      return true;
    } catch (error) {
      this.logger.error(`Deployment process failed: ${error.message}`);
      return false;
    }
  }
}

// Export the class for use in other modules
module.exports = DeploymentManager;

// If run directly, execute deployment
if (require.main === module) {
