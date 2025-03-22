/**
 * Performance Benchmarking Configuration
 */
const path = require('path');

module.exports = {
  // General benchmark settings
  settings: {
    enabled: process.env.ENABLE_BENCHMARKS !== 'false',
    logResults: process.env.LOG_BENCHMARK_RESULTS !== 'false',
    saveResults: process.env.SAVE_BENCHMARK_RESULTS !== 'false',
    resultsDir: path.resolve(__dirname, '../performance'),
    compareWithPrevious: true,
    environmentInfo: true
  },

  // Thresholds for alerting on performance regressions
  thresholds: {
    // Maximum allowed percentage increase in execution time before warning
    executionTimeWarning: 10,
    executionTimeError: 20,

    // Memory usage thresholds (in MB)
    memoryLeakWarning: 50,
    memoryLeakError: 100
  },

  // Critical paths that should always be benchmarked
  criticalPaths: [
    'photoImport',
    'photoIndexing',
    'facialRecognition',
    'thumbnailGeneration',
    'searchQueries'
  ],

  // Benchmarks to disable in production
  disableInProduction: [
    'detailedMemoryAnalysis',
    'extendedImportBenchmarks',
    'podmanStartup'  // Updated from dockerStartup to podmanStartup
  ]
};
