#!/bin/bash
set -e

# Create directory structure for Ninja CMake Team build system
echo "Setting up Ninja CMake Team build environment..."

# Base directories
mkdir -p scripts/ninja/cmake
mkdir -p scripts/ninja/cmake/modules
mkdir -p scripts/ninja/cmake/tools
mkdir -p scripts/ninja/cmake/templates
mkdir -p scripts/ninja/cmake/config
mkdir -p build/ninja/team
mkdir -p build/ninja/logs
mkdir -p build/ninja/artifacts
mkdir -p build/ninja/cache

# Create team member directories
for i in $(seq 1 12); do
  mkdir -p build/ninja/team/member-$i/workspace
  mkdir -p build/ninja/team/member-$i/logs
  mkdir -p build/ninja/team/member-$i/cache
done

# Create initial configuration file
cat > scripts/ninja/cmake/config/team-config.json << EOF
{
  "team_size": 12,
  "recursion_depth": 4,
  "build_mode": "parallel",
  "build_type": "Release",
  "enable_monitoring": true,
  "enable_benchmarks": true,
  "enable_testing": true,
  "log_level": "info"
}
EOF

echo "Ninja CMake Team environment setup complete!"
chmod +x scripts/ninja/cmake/*.sh
