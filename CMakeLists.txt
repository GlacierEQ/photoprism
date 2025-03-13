cmake_minimum_required(VERSION 3.16)
project(PhotoPrism VERSION 0.1.0 LANGUAGES C CXX Go)

# Options
option(BUILD_TESTING "Build tests" ON)
option(USE_NINJA "Use Ninja build system" ON)
option(ENABLE_BRAINS "Enable AI brains functionality" ON)
option(ENABLE_TENSORFLOW "Enable TensorFlow integration" ON)
option(BUILD_PRODUCTION "Build for production" OFF)
option(ENABLE_SANITIZERS "Enable sanitizers in debug builds" OFF)
option(BUILD_BENCHMARKS "Build benchmarks" ON)
option(USE_NINJA_TEAM "Use Ninja team for parallel builds" ON)
option(ENABLE_MONITORING "Enable monitoring" ON)
option(ENABLE_RECURSIVE_BUILD "Enable recursive build patterns" ON)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Set Go environment
set(GO_ROOT $ENV{GOPATH})
if(NOT GO_ROOT)
    set(GO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.go")
endif()

# Include directories
include_directories(${CMAKE_CURRENT_SOURCE_DIR})
include_directories(${CMAKE_SOURCE_DIR}/include)

# Find required packages
find_package(Git REQUIRED)
find_package(Threads REQUIRED)
find_package(Boost COMPONENTS system filesystem REQUIRED)

# Define build paths
set(BUILD_OUTPUT_PATH ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# Get version from Git
execute_process(
    COMMAND git describe --always
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    OUTPUT_VARIABLE GIT_VERSION
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Set build date
string(TIMESTAMP BUILD_DATE "%y%m%d" UTC)
set(BUILD_ID "${BUILD_DATE}-${GIT_VERSION}")

# Configure build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()

# Ninja team settings
set(NINJA_TEAM_SIZE 12 CACHE STRING "Number of ninja team members")
set(NINJA_RECURSION_DEPTH 4 CACHE STRING "Recursion depth for ninja builds")

# Create build configuration
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/cmake/BuildConfig.h.in
    ${CMAKE_BINARY_DIR}/generated/BuildConfig.h
)

# Add subdirectories
add_subdirectory(internal)
add_subdirectory(pkg)
add_subdirectory(scripts/ninja/cmake)
if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()

# Custom targets
add_custom_target(download_models
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/scripts/download-brains.sh
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/scripts/download-facenet.sh
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/scripts/download-nasnet.sh
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Downloading AI models"
)

add_custom_target(frontend
    COMMAND npm ci --no-update-notifier --no-audit
    COMMAND npm run build
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/frontend
    COMMENT "Building frontend"
)

add_custom_target(docker_build
    COMMAND docker compose build --pull
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Building Docker containers"
)

add_custom_target(prepare-environment
    COMMAND ${CMAKE_COMMAND} -E echo "Preparing environment for build"
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_BINARY_DIR}/build
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_BINARY_DIR}/logs
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_BINARY_DIR}/artifacts
)

add_custom_target(ninja-team-deploy
    COMMAND ${CMAKE_COMMAND} -E echo "Starting Ninja Team Deployment"
    COMMAND ${CMAKE_SOURCE_DIR}/scripts/ninja/cmake/ninja-team-deploy.sh ${NINJA_TEAM_SIZE} ${NINJA_RECURSION_DEPTH}
    DEPENDS prepare-environment
)

add_custom_target(deploy-docker
    COMMAND ${CMAKE_COMMAND} -E echo "Deploying Docker environment"
    COMMAND ${CMAKE_SOURCE_DIR}/docker/scripts/deploy.sh
    DEPENDS prepare-environment
)

# Main target
add_custom_target(photoprism ALL
    DEPENDS download_models frontend
    COMMAND go build -tags="${BUILD_TAGS}" -ldflags "-X main.version=${BUILD_ID}" -o ${BUILD_OUTPUT_PATH}/photoprism ${CMAKE_CURRENT_SOURCE_DIR}/cmd/photoprism/photoprism.go
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Building PhotoPrism"
)

# Install targets
install(
    DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/assets/
    DESTINATION assets
    PATTERN ".buildignore" EXCLUDE
)

install(
    PROGRAMS ${BUILD_OUTPUT_PATH}/photoprism
    DESTINATION bin
)

# Print build configuration
message(STATUS "PhotoPrism Build Configuration:")
message(STATUS "  Version: ${BUILD_ID}")
message(STATUS "  Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  Enable Brains: ${ENABLE_BRAINS}")
message(STATUS "  Enable TensorFlow: ${ENABLE_TENSORFLOW}")
message(STATUS "  Build Testing: ${BUILD_TESTING}")
message(STATUS "  Build benchmarks: ${BUILD_BENCHMARKS}")
message(STATUS "  Use Ninja team: ${USE_NINJA_TEAM}")
message(STATUS "  Ninja team size: ${NINJA_TEAM_SIZE}")
message(STATUS "  Recursion depth: ${NINJA_RECURSION_DEPTH}")
