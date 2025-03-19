#!/bin/bash

echo "Checking required dependencies..."

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
else
    echo "✅ Docker $(docker --version | cut -d ' ' -f3 | tr -d ',')"

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        echo "❌ Docker daemon is not running. Please start Docker and try again."
        exit 1
    fi
fi

# Check Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed."
    if command -v docker &> /dev/null; then
        echo "  You can use Docker Compose plugin with: docker compose"
        # Check if docker compose plugin exists
        if ! docker compose version &> /dev/null; then
            echo "❌ Docker Compose plugin is not available."
        else
            echo "✅ Docker Compose plugin $(docker compose version --short)"
        fi
    fi
else
    echo "✅ Docker Compose $(docker-compose --version | cut -d ' ' -f3 | tr -d ',')"
fi

# Check for curl
if ! command -v curl &> /dev/null; then
    echo "⚠️ curl is not installed. Some network checks may fail."
else
    echo "✅ curl $(curl --version | head -n 1 | cut -d ' ' -f2)"
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "⚠️ jq is not installed. Some scripts may have reduced functionality."
    echo "  Please install jq: https://stedolan.github.io/jq/download/"
else
    echo "✅ jq $(jq --version)"
fi

# Check for bc
if ! command -v bc &> /dev/null; then
    echo "⚠️ bc is not installed. Performance benchmarks and some calculations will not work correctly."
    echo "  Please install bc using your package manager (e.g., apt-get install bc, yum install bc, brew install bc)."
else
    echo "✅ bc $(bc --version | head -n 1)"
fi

# Check for openssl
if ! command -v openssl &> /dev/null; then
    echo "⚠️ openssl is not installed. Password generation will not work."
    echo "  Please install openssl using your package manager."
else
    echo "✅ OpenSSL $(openssl version | cut -d ' ' -f2)"
fi

# Check bash version (we need 4.0+ for some features)
bash_version=$(bash --version | head -n1 | cut -d ' ' -f4 | cut -d '.' -f1)
if [ "$bash_version" -lt 4 ]; then
    echo "⚠️ Bash version $bash_version detected. Some scripts require Bash 4.0+."
    echo "  This may cause issues on macOS which ships with Bash 3.2."
else
    echo "✅ Bash $(bash --version | head -n1 | cut -d ' ' -f4)"
fi

echo -e "\nSystem resources:"
# Check memory
if command -v free &> /dev/null; then
    total_mem=$(free -m | awk '/^Mem:/ {print $2}')
    echo "  Memory: ${total_mem}MB total"
    if [ $total_mem -lt 4000 ]; then
        echo "⚠️ Less than 4GB RAM available. Performance may be affected."
    fi
fi

# Check disk space
disk_space=$(df -h . | awk 'NR==2 {print $4}')
echo "  Disk space: $disk_space available"

echo -e "\nReady to proceed? Run ./scripts/quickstart.sh to begin setup."
