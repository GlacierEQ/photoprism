# Custom build targets for PhotoPrism

# Build with optimized settings
.PHONY: optimize
optimize:
	@echo "Building with optimized settings..."
	@$(MAKE) -f Makefile.ninja CMAKE_BUILD_TYPE=Release build

# Build with debug settings
.PHONY: debug
debug:
	@echo "Building with debug settings..."
	@$(MAKE) -f Makefile.ninja CMAKE_BUILD_TYPE=Debug build

# Build with race detection
.PHONY: race
race:
	@echo "Building with race detection..."
	@GO_RACE_FLAGS="-race" $(MAKE) -f Makefile.ninja build

# Generate documentation
.PHONY: docs
docs:
	@echo "Generating documentation..."
	@go run cmd/photoprism/photoprism.go generate docs
	@cd frontend && npm run docs

# Build for multiple platforms
.PHONY: cross-platform
cross-platform:
	@echo "Building for multiple platforms..."
	@for os in linux darwin windows; do \
		for arch in amd64 arm64; do \
			echo "Building for $$os/$$arch..."; \
			GOOS=$$os GOARCH=$$arch go build -o $(BUILD_DIR)/photoprism-$$os-$$arch$(if $(filter windows,$$os),.exe,) ./cmd/photoprism; \
		done; \
	done

# Create distribution packages
.PHONY: dist
dist: build
	@echo "Creating distribution packages..."
	@$(MKDIR) $(BUILD_DIR)/dist
	@tar czf $(BUILD_DIR)/dist/photoprism-$(shell date +%Y%m%d).tar.gz -C $(INSTALL_DIR) .
	@zip -r $(BUILD_DIR)/dist/photoprism-$(shell date +%Y%m%d).zip $(INSTALL_DIR)
	@echo "Packages created in $(BUILD_DIR)/dist"

# Build with Docker
.PHONY: docker-build
docker-build:
	@echo "Building with Docker..."
	@docker run --rm -v $(PWD):/app -w /app photoprism/develop:latest make -f Makefile.ninja build

# Deploy to Kubernetes
.PHONY: k8s-deploy
k8s-deploy: docker
	@echo "Deploying to Kubernetes..."
	@kubectl apply -f kubernetes/photoprism.yaml

# Create a development environment
.PHONY: dev-env
dev-env:
	@echo "Setting up development environment..."
	@go mod download
	@cd frontend && npm ci
	@echo "Development environment is ready"

# Create a release
.PHONY: release
release:
	@echo "Creating new release..."
	@read -p "Enter version (e.g., 1.0.0): " version; \
	git tag -a "v$$version" -m "Release v$$version"; \
	git push origin "v$$version"

# Benchmark the application
.PHONY: bench
bench:
	@echo "Running benchmarks..."
	@go test -bench=. -benchmem ./...

# Custom Ninja Team Makefile targets

# Variables
NINJA_TEAM_SIZE ?= 3
NINJA_RECURSION_LEVELS ?= 2
NINJA_BUILD_MODE ?= "parallel"
BUILD_DIR ?= build/ninja
DEPLOYMENT_ENV ?= production

# Ninja team deployment targets
ninja-deploy:
	@echo "====== Ninja Team Deployment ======"
	@echo "Using team size: $(NINJA_TEAM_SIZE)"
	@echo "Recursion levels: $(NINJA_RECURSION_LEVELS)"
	@echo "Build mode: $(NINJA_BUILD_MODE)"
	@echo "=================================="
	@mkdir -p $(BUILD_DIR)/logs
	@TEAM_SIZE=$(NINJA_TEAM_SIZE) \
	RECURSION_LEVELS=$(NINJA_RECURSION_LEVELS) \
	BUILD_MODE=$(NINJA_BUILD_MODE) \
	DEPLOYMENT_ENV=$(DEPLOYMENT_ENV) \
	./scripts/ninja/deploy.sh 2>&1 | tee $(BUILD_DIR)/logs/deployment-$(shell date +%Y%m%d-%H%M%S).log

ninja-setup:
	@echo "Setting up Ninja Team environment..."
	@mkdir -p scripts/ninja
	@mkdir -p $(BUILD_DIR)/config $(BUILD_DIR)/state
	@if [ ! -f scripts/ninja/deploy.sh ]; then \
		echo "Creating deployment script..."; \
		cp scripts/ninja/deploy.sh.example scripts/ninja/deploy.sh; \
		chmod +x scripts/ninja/deploy.sh; \
	fi
	@echo "Configuration complete. Next steps:"
	@echo "1. Edit scripts/ninja/ninja-team.yml.example with your settings"
	@echo "2. Run 'make ninja-init' to initialize the team"
	@echo "3. Run 'make ninja-deploy' to start deployment"

ninja-init:
	@echo "Initializing Ninja Team with size $(NINJA_TEAM_SIZE)..."
	@mkdir -p $(BUILD_DIR)
	@for i in $$(seq 1 $(NINJA_TEAM_SIZE)); do \
		mkdir -p $(BUILD_DIR)/ninja-$$i/config; \
		mkdir -p $(BUILD_DIR)/ninja-$$i/state; \
		echo "{\"id\": $$i, \"ready\": true, \"status\": \"initialized\"}" > $(BUILD_DIR)/ninja-$$i/agent-info.json; \
		echo "Initialized ninja $$i"; \
	done
	@cp scripts/ninja/ninja-team.yml.example $(BUILD_DIR)/config/ninja-team.yml
	@echo "Ninja team initialization complete."
	@echo "Ready for deployment with: make ninja-deploy"

ninja-status:
	@echo "Checking ninja team status..."
	@if [ -f $(BUILD_DIR)/deployment-status.json ]; then \
		cat $(BUILD_DIR)/deployment-status.json; \
	else \
		echo "No deployment status found"; \
	fi
	@for i in $$(seq 1 $(NINJA_TEAM_SIZE)); do \
		if [ -f $(BUILD_DIR)/ninja-$$i/agent-info.json ]; then \
			echo "Agent $$i:"; \
			cat $(BUILD_DIR)/ninja-$$i/agent-info.json; \
		else \
			echo "Agent $$i: Not initialized"; \
		fi; \
	done

ninja-clean:
	@echo "Cleaning ninja team build artifacts..."
	@for i in $$(seq 1 $(NINJA_TEAM_SIZE)); do \
		rm -rf $(BUILD_DIR)/ninja-$$i; \
		echo "Cleaned build directory for ninja $$i"; \
	done
	@rm -f $(BUILD_DIR)/deployment-status.json
	@rm -f $(BUILD_DIR)/logs/*
	@echo "Ninja team cleanup complete."

ninja-rollback:
	@echo "Rolling back to previous deployment..."
	@if [ -f $(BUILD_DIR)/state/previous-deployment.json ]; then \
		cat $(BUILD_DIR)/state/previous-deployment.json; \
		echo "Executing rollback..."; \
		./scripts/ninja/rollback.sh; \
	else \
		echo "No previous deployment found for rollback"; \
	fi
