const path = require('path');
const fs = require('fs').promises;
const fsSync = require('fs');
const os = require('os');
const DependencyVerifier = require('./verify-dependencies');
const logger = require('./utils/logger');

/**
 * Project initializer class
 * Handles initialization of the project after dependency verification
 */
class ProjectInitializer {
  constructor(options = {}) {
    this.logger = logger.getLogger('initializer');
    this.configDir = path.resolve(__dirname, '../config');
    this.configPath = path.resolve(this.configDir, 'app-config.json');
    this.templatePath = path.resolve(this.configDir, 'app-config.template.json');
    this.options = {
      skipDependencyCheck: false,
      forceReinitialize: false,
      ...options
    };
  }

  /**
   * Load configuration from file or create default
   * @returns {Promise<Object>} Loaded configuration
   */
  async loadConfig() {
    try {
      this.logger.info('Loading configuration...');

      // Check if config exists
      try {
        await fs.access(this.configPath);
        const configData = await fs.readFile(this.configPath, 'utf8');
        this.config = JSON.parse(configData);
        this.logger.info('Configuration loaded successfully');

        // Validate the loaded configuration
        this.validateConfig();
      } catch (error) {
        if (error instanceof SyntaxError) {
          this.logger.error(`Invalid JSON in configuration file: ${error.message}`);
          this.logger.info('Creating default configuration...');
          await this.createDefaultConfig();
        } else if (error.code === 'ENOENT') {
          this.logger.warn('Configuration file not found. Creating default configuration.');
          await this.createDefaultConfig();
        } else {
          throw error;
        }
      }
    } catch (error) {
      this.logger.error(`Failed to load configuration: ${error.message}`);
      throw error;
    }

    return this.config;
  }

  /**
   * Create default configuration
   * @returns {Promise<void>}
   */
  async createDefaultConfig() {
    try {
      // Try to load from template if exists
      if (fsSync.existsSync(this.templatePath)) {
        const templateData = await fs.readFile(this.templatePath, 'utf8');
        this.config = JSON.parse(templateData);
        this.logger.info('Using template configuration');
      } else {
        // Create new default config
        this.config = {
          environment: process.env.NODE_ENV || 'development',
          port: parseInt(process.env.PORT || '3000', 10),
          logLevel: process.env.LOG_LEVEL || 'info',
          initialized: false,
          security: {
            apiKeys: [],
            cookieSecret: this.generateRandomString(32),
            sessionTimeout: 3600
          },
          storage: {
            photoDir: path.resolve(__dirname, '../storage/photos'),
            tempDir: path.resolve(__dirname, '../temp'),
            maxUploadSize: 1024 * 1024 * 100 // 100 MB
          },
          database: {
            host: process.env.DB_HOST || 'localhost',
            port: parseInt(process.env.DB_PORT || '3306', 10),
            user: process.env.DB_USER || 'photoprism',
            password: process.env.DB_PASSWORD || 'password',
            database: process.env.DB_NAME || 'photoprism',
            ssl: process.env.DB_SSL === 'true'
          },
          system: {
            hostname: os.hostname(),
            platform: os.platform(),
            cpuCores: os.cpus().length,
            totalMemory: os.totalmem(),
            freeMemory: os.freemem()
          }
        };
      }

      await this.saveConfig();
    } catch (error) {
      this.logger.error(`Failed to create default configuration: ${error.message}`);
      throw error;
    }
  }

  /**
   * Validate configuration fields
   * @throws {Error} If configuration is invalid
   */
  validateConfig() {
    const requiredFields = ['environment', 'port', 'logLevel'];
    const missingFields = requiredFields.filter(field => !this.config[field]);

    if (missingFields.length > 0) {
      throw new Error(`Missing required configuration fields: ${missingFields.join(', ')}`);
    }

    // Validate port is a number
    if (typeof this.config.port !== 'number' || this.config.port < 1 || this.config.port > 65535) {
      throw new Error('Invalid port number in configuration');
    }

    // Validate environment is one of allowed values
    const allowedEnvs = ['development', 'test', 'production'];
    if (!allowedEnvs.includes(this.config.environment)) {
      throw new Error(`Invalid environment: ${this.config.environment}. Must be one of ${allowedEnvs.join(', ')}`);
    }

    // Validate log level
    const allowedLogLevels = ['error', 'warn', 'info', 'debug'];
    if (!allowedLogLevels.includes(this.config.logLevel)) {
      throw new Error(`Invalid log level: ${this.config.logLevel}. Must be one of ${allowedLogLevels.join(', ')}`);
    }
  }

  /**
   * Generate random string for security purposes
   * @param {number} length - Length of string to generate
   * @returns {string} Random string
   */
  generateRandomString(length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    const randomBytes = Buffer.alloc(length);

    try {
      require('crypto').randomFillSync(randomBytes);
      for (let i = 0; i < length; i++) {
        result += chars[randomBytes[i] % chars.length];
      }
    } catch (error) {
      // Fallback to less secure Math.random()
      for (let i = 0; i < length; i++) {
        result += chars.charAt(Math.floor(Math.random() * chars.length));
      }
    }

    return result;
  }

  /**
   * Save configuration to file
   * @returns {Promise<void>}
   */
  async saveConfig() {
    try {
      const configDir = path.dirname(this.configPath);

      try {
        await fs.access(configDir);
      } catch {
        await fs.mkdir(configDir, { recursive: true });
      }

      await fs.writeFile(
        this.configPath,
        JSON.stringify(this.config, null, 2),
        'utf8'
      );

      this.logger.info('Configuration saved successfully');
    } catch (error) {
      this.logger.error(`Failed to save configuration: ${error.message}`);
      throw error;
    }
  }

  /**
   * Create necessary directories for the project
   * @returns {Promise<void>}
   */
  async createDirectories() {
    const dirs = [
      path.resolve(__dirname, '../data'),
      path.resolve(__dirname, '../logs'),
      path.resolve(__dirname, '../temp'),
      path.resolve(__dirname, '../storage'),
      path.resolve(__dirname, '../storage/photos'),
      path.resolve(__dirname, '../storage/thumbnails'),
      path.resolve(__dirname, '../storage/uploads'),
      path.resolve(__dirname, '../storage/cache')
    ];

    for (const dir of dirs) {
      try {
        await fs.access(dir);
        this.logger.debug(`Directory exists: ${dir}`);
      } catch {
        this.logger.info(`Creating directory: ${dir}`);
        await fs.mkdir(dir, { recursive: true });

        // Set proper permissions on Linux/Mac
        if (os.platform() !== 'win32') {
          try {
            await fs.chmod(dir, 0o755);
          } catch (error) {
            this.logger.warn(`Failed to set permissions on ${dir}: ${error.message}`);
          }
        }
      }
    }
  }

  /**
   * Initialize the project
   * @returns {Promise<boolean>} Success status
   */
  async initialize() {
    try {
      this.logger.info('Starting project initialization...');
      const startTime = process.hrtime();

      // Check if already initialized and not forced to reinitialize
      if (!this.options.forceReinitialize) {
        try {
          const existingConfig = JSON.parse(await fs.readFile(this.configPath, 'utf8'));
          if (existingConfig.initialized) {
            this.logger.info('Project already initialized. Use forceReinitialize option to reinitialize.');
            this.config = existingConfig;
            return true;
          }
        } catch (error) {
          // If error reading config, continue with initialization
          this.logger.debug(`Could not read existing config: ${error.message}`);
        }
      }

      // Verify dependencies if not skipped
      if (!this.options.skipDependencyCheck) {
        const verifier = new DependencyVerifier();
        const dependenciesOk = await verifier.verifyAll();

        if (!dependenciesOk) {
          this.logger.error('Dependency verification failed. Please install missing dependencies.');
          return false;
        }
      }

      // Load or create configuration
      await this.loadConfig();

      // Create necessary directories
      await this.createDirectories();

      // Update config to mark as initialized
      this.config.initialized = true;
      this.config.initializedAt = new Date().toISOString();
      this.config.version = require('../package.json').version;
      await this.saveConfig();

      const [seconds, nanoseconds] = process.hrtime(startTime);
      const duration = seconds + nanoseconds / 1e9;
      this.logger.info(`Project initialized successfully in ${duration.toFixed(2)} seconds!`);
      return true;
    } catch (error) {
      this.logger.error(`Initialization failed: ${error.message}`);
      return false;
    }
  }
}

// Export the class for use in other modules
module.exports = ProjectInitializer;

// If run directly, execute initialization
if (require.main === module) {
  const initializer = new ProjectInitializer();
  initializer.initialize()
    .then(success => {
      if (!success) {
        process.exit(1);
      }
    })
    .catch(error => {
      console.error('Initialization failed:', error);
      process.exit(1);
    });
}
