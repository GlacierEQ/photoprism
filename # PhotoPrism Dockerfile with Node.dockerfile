# PhotoPrism Dockerfile with Node.js support
FROM node:14-bullseye

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV DOCKER_COMPOSE_VERSION=v2.21.0
ENV PHOTOPRISM_UID=1000
ENV PHOTOPRISM_GID=1000
ENV PHOTOPRISM_INIT="update tensorflow"
ENV NODE_ENV=production

# Install PhotoPrism dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    sudo \
    bash \
    docker.io \
    docker-compose \
    python3 \
    python3-pip \
    ffmpeg \
    libheif-dev \
    libvips-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Docker Compose
RUN curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose

# Set up working directory
WORKDIR /app

# Copy package.json files first for better caching
COPY package*.json ./

# Install Node.js dependencies
RUN npm ci --only=production || npm install --production

# Copy the rest of the application code
COPY . .

# Add script to fix line endings and make it executable
COPY scripts/fix-line-endings.sh /app/scripts/fix-line-endings.sh
RUN chmod +x /app/scripts/fix-line-endings.sh
RUN /app/scripts/fix-line-endings.sh

# Make the deployment script executable
RUN chmod +x scripts/deploy-production.sh

# Create photoprism user and group
RUN groupadd -g ${PHOTOPRISM_GID} photoprism || true && \
    useradd -u ${PHOTOPRISM_UID} -g photoprism -s /bin/bash -m photoprism || true && \
    chown -R photoprism:photoprism /app

# Create necessary directories
RUN mkdir -p /photoprism/storage/originals && \
    chown -R photoprism:photoprism /photoprism

# Switch to photoprism user
USER photoprism

# Define volumes
VOLUME ["/photoprism/storage", "/photoprism/storage/originals"]

# Expose ports - PhotoPrism on 2342, Node app on 3000
EXPOSE 2342 3000

# Create a startup script with proper line endings
RUN echo '#!/bin/bash\n\
# Start PhotoPrism deployment in background\n\
/app/scripts/deploy-production.sh &\n\
# Start Node.js application\n\
npm start' > /app/start.sh && \
    chmod +x /app/start.sh && \
    sed -i 's/\r$//' /app/start.sh

# Command to run both applications
CMD ["/app/start.sh"]
