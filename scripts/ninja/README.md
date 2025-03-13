# PhotoPrism Ninja Team Deployment System

A professional, highly parallel, and recursive deployment system for PhotoPrism using Ninja and CMake.

## Features

- **Ninja Team Deployment**: Utilizes 12 specialized ninja team members for parallel tasks
- **Recursive Optimization**: Implements 4 levels of recursion for thorough optimization
- **Advanced Monitoring**: Real-time performance metrics and health checks
- **Professional Reporting**: Detailed HTML reports with deployment statistics
- **Automated Recovery**: Intelligent error handling with rollback capabilities
- **Resource Management**: Optimized allocation of CPU, memory, and disk resources
- **Security Integration**: Built-in security scanning and validation

## Requirements

- Docker & Docker Compose
- CMake 3.16+ (recommended)
- Ninja build system (recommended)
- jq (for JSON processing)
- Bash shell

## Usage

### Quick Start

To deploy PhotoPrism using the Ninja Team system:

```bash
chmod +x deploy-ninja.sh
./deploy-ninja.sh
```

### Configuration

You can customize the deployment by editing the `deploy-config.json` file:

- **Team Size**: Number of ninja team members (max 12)
- **Recursion Depth**: How deep the optimization goes (1-4)
- **Build Mode**: parallel, sequential, or adaptive
- **Environment**: production, staging, or development

### Advanced Usage

For more control, you can use the underlying scripts directly:

```bash
# Initialize the ninja team
scripts/ninja/cmake/tools/init_team.sh 12

# Deploy with specific parameters
TEAM_SIZE=12 RECURSION_DEPTH=4 BUILD_MODE="parallel" scripts/ninja/cmake/ninja-team-deploy.sh

# Generate a deployment report
scripts/ninja/cmake/tools/generate_report.sh
```

## Architecture

The Ninja Team system works by distributing tasks across specialized ninja team members, each with specific capabilities. The system uses recursion to progressively optimize each aspect of the deployment.

### Team Member Roles

1. **Lead Ninja**: Coordinates the deployment process
2. **Network Ninja**: Handles network configuration and security
3. **Database Ninja**: Manages database setup and optimization
4. **Frontend Ninja**: Optimizes the UI components
5. **Backend Ninja**: Handles API and backend services
6. **Security Ninja**: Implements security measures
7. **Testing Ninja**: Conducts validation tests
8. **Infrastructure Ninja**: Manages system resources
9. **Optimization Ninja**: Focuses on performance tuning
10. **Monitoring Ninja**: Sets up logging and alerting
11. **Backup Ninja**: Handles data protection
12. **Deployment Ninja**: Manages the actual deployment

## Monitoring

The system includes built-in monitoring that collects:

- CPU usage
- Memory utilization
- Disk space
- Task completion rates
- Error rates

## Reporting

After deployment, an HTML report is generated with:

- Deployment summary
- Team performance statistics
- Task completion metrics
- Resource utilization
- Next steps

## Troubleshooting

If deployment fails:

1. Check the log file in `build/ninja/logs/`
2. Review the team member status files in `build/ninja/team/member-*/status.json`
3. Run `scripts/ninja/cmake/tools/diagnose.sh` for a detailed analysis

## License

See the main PhotoPrism license for details.
