const fs = require('fs');
const path = require('path');
const util = require('util');
const os = require('os');

/**
 * Constants for log rotation
 */
const DEFAULT_MAX_SIZE = 10 * 1024 * 1024; // 10 MB
const DEFAULT_MAX_FILES = 5;
const DEFAULT_LOG_LEVEL = 'info';

/**
 * Logger utility for consistent logging across the application
 * Includes log rotation and configurable formats
 */
class Logger {
  /**
   * Create a new logger instance
   * @param {string} module - Module name for categorizing logs
   * @param {Object} options - Logger options
   */
  constructor(module, options = {}) {
    this.module = module;
    this.options = {
      logLevel: process.env.LOG_LEVEL || DEFAULT_LOG_LEVEL,
      logDir: path.resolve(__dirname, '../../logs'),
      maxSize: parseInt(process.env.LOG_MAX_SIZE || DEFAULT_MAX_SIZE, 10),
      maxFiles: parseInt(process.env.LOG_MAX_FILES || DEFAULT_MAX_FILES, 10),
      logToConsole: process.env.LOG_TO_CONSOLE !== 'false',
      logToFile: process.env.LOG_TO_FILE !== 'false',
      colorize: process.env.LOG_COLORIZE !== 'false' && process.stdout.isTTY,
      ...options
    };

    this.levels = {
      error: 0,
      warn: 1,
      info: 2,
      debug: 3
    };

    this.colors = {
      error: '\x1b[31m', // Red
      warn: '\x1b[33m',  // Yellow
      info: '\x1b[36m',  // Cyan
      debug: '\x1b[90m', // Gray
      reset: '\x1b[0m'   // Reset
    };

    // Create logs directory if it doesn't exist
    this.ensureLogDirectory();

    this.logFile = path.join(this.options.logDir, 'application.log');
    this.syncPending = false;
    this.buffer = [];

    // Set up periodic flush for buffered logs
    this.flushInterval = setInterval(() => this.flushBuffer(), 1000);

    // Handle process exit
    process.on('beforeExit', () => {
      clearInterval(this.flushInterval);
      this.flushBuffer(true);
    });
  }

  /**
   * Ensure log directory exists
   * @private
   */
  ensureLogDirectory() {
    try {
      if (!fs.existsSync(this.options.logDir)) {
        fs.mkdirSync(this.options.logDir, { recursive: true });
      }
    } catch (error) {
      console.error(`Failed to create log directory: ${error.message}`);
      // Fall back to system temp directory
      this.options.logDir = path.join(os.tmpdir(), 'photoprism-logs');
      if (!fs.existsSync(this.options.logDir)) {
        fs.mkdirSync(this.options.logDir, { recursive: true });
      }
    }
  }

  /**
   * Determine if message should be logged at current level
   * @param {string} level - Log level to check
   * @returns {boolean} Whether to log the message
   * @private
   */
  _shouldLog(level) {
    return this.levels[level] <= this.levels[this.options.logLevel];
  }

  /**
   * Format log message with timestamp and metadata
   * @param {string} level - Log level
   * @param {string} message - Message to format
   * @returns {string} Formatted message
   * @private
   */
  _formatMessage(level, message) {
    const timestamp = new Date().toISOString();
    return `[${timestamp}] [${level.toUpperCase()}] [${this.module}] ${message}`;
  }

  /**
   * Check if log rotation is needed
   * @private
   */
  _checkRotation() {
    try {
      if (!fs.existsSync(this.logFile)) {
        return;
      }

      const stats = fs.statSync(this.logFile);
      if (stats.size >= this.options.maxSize) {
        this._rotateLog();
      }
    } catch (error) {
      console.error(`Log rotation check failed: ${error.message}`);
    }
  }

  /**
   * Rotate log files
   * @private
   */
  _rotateLog() {
    try {
      // Shift existing logs
      for (let i = this.options.maxFiles - 1; i > 0; i--) {
        const oldPath = `${this.logFile}.${i}`;
        const newPath = `${this.logFile}.${i + 1}`;

        if (fs.existsSync(oldPath)) {
          if (i === this.options.maxFiles - 1) {
            // Delete oldest log
            fs.unlinkSync(oldPath);
          } else {
            // Rename to next number
            fs.renameSync(oldPath, newPath);
          }
        }
      }

      // Rename current log
      if (fs.existsSync(this.logFile)) {
        fs.renameSync(this.logFile, `${this.logFile}.1`);
      }
    } catch (error) {
      console.error(`Log rotation failed: ${error.message}`);
    }
  }

  /**
   * Buffer log message for writing to file
   * @param {string} formattedMessage - Message to buffer
   * @private
   */
  _bufferLogMessage(formattedMessage) {
    this.buffer.push(formattedMessage);

    // If buffer gets too large, flush immediately
    if (this.buffer.length >= 100) {
      this.flushBuffer();
    }
  }

  /**
   * Flush buffered log messages to file
   * @param {boolean} sync - Whether to flush synchronously
   */
  flushBuffer(sync = false) {
    if (this.buffer.length === 0 || this.syncPending) {
      return;
    }

    this.syncPending = true;
    const messages = this.buffer.join('\n') + '\n';
    this.buffer = [];

    // Check if rotation needed
    this._checkRotation();

    try {
      if (sync) {
        fs.appendFileSync(this.logFile, messages);
        this.syncPending = false;
      } else {
        fs.appendFile(this.logFile, messages, err => {
          this.syncPending = false;
          if (err) {
            console.error(`Failed to write to log file: ${err.message}`);
          }
        });
      }
    } catch (error) {
      this.syncPending = false;
      console.error(`Failed to write to log file: ${error.message}`);
    }
  }

  /**
   * Log an error message
   * @param {string} message - Message to log
   * @param {...any} args - Additional arguments for formatting
   */
  error(message, ...args) {
    if (this._shouldLog('error')) {
      const formattedMsg = this._formatMessage('error', util.format(message, ...args));

      if (this.options.logToConsole) {
        if (this.options.colorize) {
          console.error(`${this.colors.error}${formattedMsg}${this.colors.reset}`);
        } else {
          console.error(formattedMsg);
        }
      }

      if (this.options.logToFile) {
        this._bufferLogMessage(formattedMsg);
      }
    }
  }

  /**
   * Log a warning message
   * @param {string} message - Message to log
   * @param {...any} args - Additional arguments for formatting
   */
  warn(message, ...args) {
    if (this._shouldLog('warn')) {
      const formattedMsg = this._formatMessage('warn', util.format(message, ...args));

      if (this.options.logToConsole) {
        if (this.options.colorize) {
          console.warn(`${this.colors.warn}${formattedMsg}${this.colors.reset}`);
        } else {
          console.warn(formattedMsg);
        }
      }

      if (this.options.logToFile) {
        this._bufferLogMessage(formattedMsg);
      }
    }
  }

  /**
   * Log an info message
   * @param {string} message - Message to log
   * @param {...any} args - Additional arguments for formatting
   */
  info(message, ...args) {
    if (this._shouldLog('info')) {
      const formattedMsg = this._formatMessage('info', util.format(message, ...args));

      if (this.options.logToConsole) {
        if (this.options.colorize) {
          console.info(`${this.colors.info}${formattedMsg}${this.colors.reset}`);
        } else {
          console.info(formattedMsg);
        }
      }

      if (this.options.logToFile) {
        this._bufferLogMessage(formattedMsg);
      }
    }
  }

  /**
   * Log a debug message
   * @param {string} message - Message to log
   * @param {...any} args - Additional arguments for formatting
   */
  debug(message, ...args) {
    if (this._shouldLog('debug')) {
      const formattedMsg = this._formatMessage('debug', util.format(message, ...args));

      if (this.options.logToConsole) {
        if (this.options.colorize) {
          console.debug(`${this.colors.debug}${formattedMsg}${this.colors.reset}`);
        } else {
          console.debug(formattedMsg);
        }
      }

      if (this.options.logToFile) {
        this._bufferLogMessage(formattedMsg);
      }
    }
  }
}

/**
 * Logger factory module
 */
class LoggerFactory {
  constructor() {
    this.loggers = {};

    // Set up cleanup for process exit
    process.on('beforeExit', () => {
      Object.values(this.loggers).forEach(logger => {
        if (logger.flushInterval) {
          clearInterval(logger.flushInterval);
          logger.flushBuffer(true);
        }
      });
    });
  }

  /**
   * Get or create a logger instance for a module
   * @param {string} module - Module name
   * @param {Object} options - Logger options
   * @returns {Logger} Logger instance
   */
  getLogger(module, options = {}) {
    if (!this.loggers[module]) {
      this.loggers[module] = new Logger(module, options);
    }
    return this.loggers[module];
  }
}

// Create a singleton instance
const loggerFactory = new LoggerFactory();

// Export the factory
module.exports = loggerFactory;
