## Automated Build Script

The `automate-build.sh` script is a unified tool for building Docker images. It combines functionalities from previous scripts and allows for various configurations.

### Usage

```bash
./scripts/automate-build.sh [options]
```

### Options:
- `-t, --tag <tag>`: Set image tag (default: latest)
- `-f, --file <path>`: Path to Dockerfile (default: ./Dockerfile)
- `--platform <platform>`: Build platform (default: linux/amd64)
- `--no-cache`: Disable build cache
- `--build-arg <arg>`: Add build arguments (can be used multiple times)
- `-h, --help`: Display help message

### Examples:
- Basic build: `./scripts/automate-build.sh`
- Build with a specific tag: `./scripts/automate-build.sh --tag v1.0.0`
- Build for multiple platforms: `./scripts/automate-build.sh --platform linux/amd64,linux/arm64`
- Clean build without cache: `./scripts/automate-build.sh --no-cache`
