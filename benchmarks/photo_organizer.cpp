#include "benchmark_framework.h"
#include <filesystem>
#include <unordered_map>
#include <vector>
#include <string>
#include <thread>
#include <mutex>
#include <atomic>
#include <fstream>
#include <iostream>
#include <chrono>

namespace fs = std::filesystem;

// Configuration structure for file organization
struct OrganizerConfig {
    std::string sourcePath;
    std::string targetPath;
    int threadCount = 4;
    bool preserveOriginals = true;
    bool extractMetadata = true;
    int thumbnailSize = 256;
    std::string logLevel = "info";
    std::vector<std::string> categoryFolders = {
        "Documents", "Images", "Videos", "Audio", "Archives", "Other"
    };
};

// File metadata structure
struct FileMetadata {
    std::string path;
    std::string filename;
    std::string extension;
    uint64_t size;
    std::time_t creationTime;
    std::time_t modificationTime;
    std::string mimeType;
    std::string category;
};

// Photo organization class with ethical features
class PhotoOrganizer {
private:
    OrganizerConfig config;
    std::atomic<int> processedFiles{0};
    std::atomic<int> totalFiles{0};
    std::mutex logMutex;

    // Maps extensions to categories
    std::unordered_map<std::string, std::string> extensionMap = {
        {".jpg", "Images"}, {".jpeg", "Images"}, {".png", "Images"}, {".gif", "Images"},
        {".mp4", "Videos"}, {".mov", "Videos"}, {".avi", "Videos"},
        {".pdf", "Documents"}, {".doc", "Documents"}, {".docx", "Documents"},
        {".mp3", "Audio"}, {".wav", "Audio"}, {".flac", "Audio"},
        {".zip", "Archives"}, {".rar", "Archives"}, {".tar", "Archives"}
    };

    void log(const std::string& message) {
        std::lock_guard<std::mutex> lock(logMutex);
        std::cout << "[" << getCurrentTimeString() << "] " << message << std::endl;
    }

    std::string getCurrentTimeString() {
        auto now = std::chrono::system_clock::now();
        auto nowTime = std::chrono::system_clock::to_time_t(now);
        std::string timeStr = std::ctime(&nowTime);
        timeStr.pop_back(); // Remove trailing newline
        return timeStr;
    }

    std::string getFileCategory(const fs::path& filePath) {
        std::string ext = filePath.extension().string();
        std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);

        auto it = extensionMap.find(ext);
        if (it != extensionMap.end()) {
            return it->second;
        }
        return "Other";
    }

    FileMetadata extractMetadata(const fs::path& filePath) {
        FileMetadata metadata;
        metadata.path = filePath.string();
        metadata.filename = filePath.filename().string();
        metadata.extension = filePath.extension().string();

        std::error_code ec;
        auto fileStatus = fs::status(filePath, ec);
        if (!ec) {
            try {
                metadata.size = fs::file_size(filePath);
                auto lastWrite = fs::last_write_time(filePath);
                metadata.modificationTime = decltype(lastWrite)::clock::to_time_t(lastWrite);
                metadata.category = getFileCategory(filePath);
            } catch (const std::exception& e) {
                log("Error extracting metadata for " + filePath.string() + ": " + e.what());
            }
        }

        return metadata;
    }

    void processFile(const fs::path& filePath) {
        try {
            // Extract metadata
            FileMetadata metadata = extractMetadata(filePath);

            // Create category directory if it doesn't exist
            fs::path targetDir = fs::path(config.targetPath) / metadata.category;
            if (!fs::exists(targetDir)) {
                fs::create_directories(targetDir);
            }

            // Copy or move file to target directory
            fs::path targetPath = targetDir / filePath.filename();
            if (config.preserveOriginals) {
                fs::copy_file(filePath, targetPath, fs::copy_options::overwrite_existing);
                log("Copied: " + filePath.string() + " to " + targetPath.string());
            } else {
                fs::rename(filePath, targetPath);
                log("Moved: " + filePath.string() + " to " + targetPath.string());
            }

            processedFiles++;
        } catch (const std::exception& e) {
            log("Error processing file " + filePath.string() + ": " + e.what());
        }
    }

    void workerThread(const std::vector<fs::path>& files, size_t startIdx, size_t endIdx) {
        for (size_t i = startIdx; i < endIdx && i < files.size(); i++) {
            processFile(files[i]);
        }
    }

public:
    PhotoOrganizer(const OrganizerConfig& cfg) : config(cfg) {}

    void organize() {
        // Validate paths
        if (!fs::exists(config.sourcePath)) {
            log("Error: Source path does not exist: " + config.sourcePath);
            return;
        }

        if (!fs::exists(config.targetPath)) {
            fs::create_directories(config.targetPath);
        }

        // Create category folders
        for (const auto& category : config.categoryFolders) {
            fs::path categoryPath = fs::path(config.targetPath) / category;
            if (!fs::exists(categoryPath)) {
                fs::create_directories(categoryPath);
            }
        }

        // Collect files
        std::vector<fs::path> files;
        try {
            for (const auto& entry : fs::recursive_directory_iterator(config.sourcePath)) {
                if (fs::is_regular_file(entry)) {
                    files.push_back(entry.path());
                }
            }
        } catch (const std::exception& e) {
            log("Error scanning directory: " + std::string(e.what()));
            return;
        }

        totalFiles = files.size();
        log("Found " + std::to_string(totalFiles) + " files to process");

        // Process files with multiple threads
        std::vector<std::thread> threads;
        size_t filesPerThread = files.size() / config.threadCount;

        for (int i = 0; i < config.threadCount; i++) {
            size_t startIdx = i * filesPerThread;
            size_t endIdx = (i == config.threadCount - 1) ? files.size() : (i + 1) * filesPerThread;
            threads.emplace_back(&PhotoOrganizer::workerThread, this, files, startIdx, endIdx);
        }

        // Wait for all threads to complete
        for (auto& thread : threads) {
            thread.join();
        }

        log("Organization complete. Processed " + std::to_string(processedFiles) + " files.");
    }

    // Benchmark methods for different organization strategies
    void benchmarkBasicOrganization() {
        // Simple file copying and basic categorization
        OrganizerConfig testConfig = config;
        testConfig.extractMetadata = false;
        testConfig.threadCount = 1;

        PhotoOrganizer organizer(testConfig);
        organizer.organize();
    }

    void benchmarkParallelOrganization() {
        // Test with multiple threads
        OrganizerConfig testConfig = config;
        testConfig.threadCount = std::thread::hardware_concurrency();

        PhotoOrganizer organizer(testConfig);
        organizer.organize();
    }

    void benchmarkMetadataExtraction() {
        // Test with full metadata extraction
        OrganizerConfig testConfig = config;
        testConfig.extractMetadata = true;

        PhotoOrganizer organizer(testConfig);
        organizer.organize();
    }
};

// Benchmark runner
int main() {
    BenchmarkFramework framework("PhotoOrganizer");

    // Configure organizer
    OrganizerConfig config;
    config.sourcePath = "../test_data/photos";
    config.targetPath = "../test_data/organized_photos";

    PhotoOrganizer organizer(config);

    // Add benchmarks
    framework.add_benchmark("Basic Organization", [&organizer]() {
        organizer.benchmarkBasicOrganization();
    }, 1);

    framework.add_benchmark("Parallel Organization", [&organizer]() {
        organizer.benchmarkParallelOrganization();
    }, 1);

    framework.add_benchmark("Metadata Extraction", [&organizer]() {
        organizer.benchmarkMetadataExtraction();
    }, 1);

    // Run benchmarks
    framework.run_all_benchmarks();

    return 0;
}
