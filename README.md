# OctoEverywhere Non-Root Wrapper Image

[![Build and Push to GHCR](https://github.com/sibest19/octoeverywhere/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/sibest19/octoeverywhere/actions/workflows/build-and-push.yml)
[![GitHub Container Registry](https://img.shields.io/badge/ghcr.io-sibest19%2Foctoeverywhere-blue?logo=docker)](https://github.com/sibest19/octoeverywhere/pkgs/container/octoeverywhere)
[![Docker Pulls](https://img.shields.io/badge/dynamic/json?color=blue&label=pulls&query=$.download_count&url=https%3A%2F%2Fghcr.io%2Fv2%2Fsibest19%2Foctoeverywhere%2Fblobs%2Fsha256%3Amanifest&logo=docker)](https://github.com/sibest19/octoeverywhere/pkgs/container/octoeverywhere)

A minimal Docker wrapper for the official `octoeverywhere/octoeverywhere` image that adds dynamic user/group ID support to fix host file permission issues.

## Problem

The official OctoEverywhere image runs as UID 1001/GID 0, causing permission issues when mounting host directories owned by different users.

## Solution

* Set any `PUID`/`PGID` at runtime - no image rebuilds needed
* Automatic ownership fix for `/data` directory on startup
* Zero maintenance - uses official image as base
* Auto-rebuilds when upstream updates

## Repository Structure

```text
sibest19/octoeverywhere/
├── Dockerfile               # Extends the official image and installs su-exec
├── entrypoint.sh            # Privilege-dropping wrapper script
└── .github/
    └── workflows/
        └── build-and-push.yml  # GH Actions workflow for CI/CD
```

## Quick Start

**Docker Compose:**
```yaml
services:
  octoeverywhere:
    image: ghcr.io/sibest19/octoeverywhere:latest
    environment:
      - PUID=1000                   # Your user ID (run `id -u`)
      - PGID=1000                   # Your group ID (run `id -g`)
      - COMPANION_MODE=elegoo
      - PRINTER_IP=192.168.1.100    # Your printer's IP
    volumes:
      - ./data:/data
    restart: unless-stopped
```

**Docker CLI:**
```bash
docker run -d \
  -e PUID=$(id -u) -e PGID=$(id -g) \
  -e COMPANION_MODE=elegoo \
  -e PRINTER_IP=192.168.1.100 \
  -v ./data:/data \
  ghcr.io/sibest19/octoeverywhere:latest
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | `1001` | User ID to run as |
| `PGID` | `0` | Group ID to run as |
| `COMPANION_MODE` | - | OctoEverywhere mode (e.g., `elegoo`) |
| `PRINTER_IP` | - | Your printer's IP address |

## How It Works

This wrapper:
1. **At build time**: Inspects the upstream image to extract its entrypoint and command
2. **At runtime**: Creates user/group with your PUID/PGID, fixes `/data` ownership, then runs the original command as that user

The wrapper automatically adapts to upstream changes without manual updates.

## Automated Builds

GitHub Actions automatically:
- Checks daily for upstream image updates
- **Detects significant changes** (entrypoint/command modifications) and alerts
- **Tests images before promotion** using comprehensive test suite
- **Maintains backup tags** (`stable-backup`) for emergency rollbacks
- Only rebuilds when upstream changes to avoid unnecessary churn
- Publishes to `ghcr.io/sibest19/octoeverywhere` with multiple tags:
  - `latest` - Current stable version (tested)
  - `stable` - Alias for latest stable
  - `stable-backup` - Previous stable version  
  - `v<version>` - Version-specific tags

### Resilience Features

- **Pre-deployment testing**: All images are tested before being tagged as `latest`
- **Change detection**: Alerts when upstream makes significant changes that might break compatibility
- **Emergency rollback**: Manual workflow to quickly revert to previous stable version
- **Health monitoring**: Standalone script for continuous monitoring (`health-check.sh`)

## Troubleshooting

### Emergency Rollback

If the latest version has issues, you can quickly rollback:

1. **Use stable backup tag:**
   ```bash
   docker pull ghcr.io/sibest19/octoeverywhere:stable-backup
   docker tag ghcr.io/sibest19/octoeverywhere:stable-backup ghcr.io/sibest19/octoeverywhere:latest
   ```

2. **Trigger automated rollback:**
   - Go to Actions → Emergency Rollback → Run workflow
   - Select the target tag (e.g., `stable-backup`) 
   - Provide a reason for the rollback

### Health Monitoring

Run the included health check script:
```bash
./health-check.sh
```

Set environment variables for alerts:
```bash
export SLACK_WEBHOOK="https://hooks.slack.com/..."
export ALERT_EMAIL="admin@example.com"
./health-check.sh
```

### Testing Changes

Test the wrapper locally:
```bash
./test-wrapper.sh ghcr.io/sibest19/octoeverywhere:latest
```

## Contributing

1. Fork the repository.
2. Create a feature branch (`git checkout -b my-feature`).
3. Commit your changes and push (`git push origin my-feature`).
4. Open a Pull Request describing your change.

Please ensure any additions keep the wrapper minimal and continue to leverage the upstream image.

---

Created and maintained by Simone Andreani ([@sibest19](https://github.com/sibest19)). Feel free to open issues or PRs for improvements.
