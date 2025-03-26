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

## PhotoPrism Clone

### Running with Docker

1.  **Build the Docker image:**

    ```bash
    docker-compose build
    ```

2.  **Run the application:**

    ```bash
    docker-compose up -d
    ```

3.  **Access the application** at `http://localhost:3000`.

### Running with Docker Compose

1.  **Navigate to the project directory:**

    ```bash
    cd photoprism2
    ```

2.  **Build the Docker image:**

    ```bash
    docker-compose build
    ```

3.  **Start the application using Docker Compose:**

    ```bash
    docker-compose up -d
    ```

4.  **Access the application** at `http://localhost:2342` (or the port you have mapped in `docker-compose.yml`).

5.  **Stop the application:**

    ```bash
    docker-compose down
    ```

## Running with Podman Compose (Alternative)

1.  **Navigate to the project directory:**

    ```bash
    cd photoprism2
    ```

2.  **Set the `PODMAN_ENABLED` build argument to `true`:**

    ```bash
    docker-compose build --build-arg PODMAN_ENABLED=true
    ```

3.  **Start the application using Podman Compose:**

    ```bash
    docker-compose -f docker-compose.yml up -d
    ```

    *Note: Ensure `podman-compose` is installed and configured.*

4.  **Access the application** at `http://localhost:2342` (or the port you have mapped in `docker-compose.yml`).

5.  **Stop the application:**

    ```bash
    docker-compose down
    ```

*Note: If you encounter issues with Podman, ensure it is properly installed and configured. You may need to start the Podman machine if you are on Windows or macOS.*

*Note: The application now uses `entrypoint.sh` to handle startup and logging.*

### Development

1.  **Install dependencies:**

    ```bash
    npm install
    ```

2.  **Run the application:**

    ```bash
    npm start
    ```
