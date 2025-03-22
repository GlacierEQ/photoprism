# PhotoPrism2

PhotoPrism2 is an extended version of PhotoPrism, using Podman for containerization.

## Requirements

- Node.js 14 or later
- Podman
- Podman Compose

## Quick Start

1. Initialize the project:
   ```bash
   npm run init
   ```

2. Deploy with Podman:
   ```bash
   npm run deploy
   ```

3. Or run step-by-step:
   ```bash
   # Start PhotoPrism containers
   npm run podman:up

   # View logs
   npm run podman:logs

   # Stop containers
   npm run podman:down
   ```

## Configuration

Default configuration files are created in the following locations:
- Main configuration: `config/app-config.json`
- Podman configuration: `podman/podman-compose.prod.yml` and `podman/.env.prod`

## Troubleshooting

If you encounter issues with Podman:
```bash
npm run podman:troubleshoot
```

## More Information

For detailed usage instructions, see [USAGE-GUIDE.md](USAGE-GUIDE.md)

## Automated Build Script

The `automate-build.sh` script is a unified tool for building Podman images. It combines functionalities from previous scripts and allows for various configurations.

### Usage

```bash
./scripts/automate-build.sh [options]
```

### Options:
- `-t, --tag <tag>`: Set image tag (default: latest)
- `-f, --file <path>`: Path to Containerfile (default: ./Containerfile)
- `--platform <platform>`: Build platform (default: linux/amd64)
- `--no-cache`: Disable build cache
- `--build-arg <arg>`: Add build arguments (can be used multiple times)
- `-h, --help`: Display help message

### Examples:
- Basic build: `./scripts/automate-build.sh`
- Build with a specific tag: `./scripts/automate-build.sh --tag v1.0.0`
- Build for multiple platforms: `./scripts/automate-build.sh --platform linux/amd64,linux/arm64`
- Clean build without cache: `./scripts/automate-build.sh --no-cache`
