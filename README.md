# OctoEverywhere Non-Root Wrapper Image

[![Build and Push to GHCR](https://github.com/sibest19/octoeverywhere/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/sibest19/octoeverywhere/actions/workflows/build-and-push.yml)
[![GitHub Container Registry](https://img.shields.io/badge/ghcr.io-sibest19%2Foctoeverywhere-blue?logo=docker)](https://github.com/sibest19/octoeverywhere/pkgs/container/octoeverywhere)

A Docker wrapper that fixes file permission issues with the official [OctoEverywhere](https://octoeverywhere.com) image by allowing you to set your own user/group IDs.

> **What is OctoEverywhere?** A service that provides remote access, AI failure detection, and notifications for 3D printers.

## The Problem

The official image does not document configurable `PUID`/`PGID` mapping. Bind-mounted data can have ownership that differs from your host user (typically UID 1000). This wrapper sets the application UID/GID and repairs `/data` ownership before launch.

## The Solution

* **Runtime user mapping**: Set `PUID`/`PGID` to match your host user
* **Automatic permissions**: Fixes `/data` directory ownership on startup  
* **Zero maintenance**: Stays updated with official releases automatically
* **Drop-in replacement**: Same usage as official image, just add PUID/PGID

## Repository Structure

```text
sibest19/octoeverywhere/
├── Dockerfile               # Extends the official image and installs su-exec
├── entrypoint.sh            # Privilege-dropping wrapper script
├── health-check.sh          # Health monitoring script with alerts
├── test-wrapper.sh          # Comprehensive test suite
└── .github/
    └── workflows/
        ├── build-and-push.yml  # CI/CD pipeline for automated builds
        ├── rollback.yml        # Emergency rollback workflow
        └── health-check.yml    # Automated health monitoring
```

## Usage

**Get your user/group IDs first:**
```bash
echo "PUID=$(id -u) PGID=$(id -g)"
```

**Docker Compose:**
```yaml
services:
  octoeverywhere:
    image: ghcr.io/sibest19/octoeverywhere:latest
    environment:
      - PUID=1000                   # Replace with your user ID
      - PGID=1000                   # Replace with your group ID
      - COMPANION_MODE=elegoo       # Your printer type
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

| Variable | Description | Example |
|----------|-------------|---------|
| `PUID` | Your user ID (run `id -u`) | `1000` |
| `PGID` | Your group ID (run `id -g`) | `1000` |
| `COMPANION_MODE` | Printer type | `elegoo`, `bambu` |
| `PRINTER_IP` | Printer's network address | `192.168.1.100` |

## How It Works

1. **Build time**: Extracts the official image's startup command
2. **Runtime**: Creates a user with your PUID/PGID, fixes `/data` ownership, then runs the original command as that user

The wrapper starts as root to prepare permissions, then replaces itself with the upstream process running as the requested user. This is separate from Docker’s rootless daemon mode.

`PUID` and `PGID` must be decimal integers without leading zeros (defaults: `1001` and `0`). `PUID` must be nonzero so the application runs without root privileges. Startup stops if user creation or `/data` ownership changes fail, including on read-only or root-squashed mounts.

Upstream `ENTRYPOINT` and `CMD` are stored as JSON so spaces, quotes, and empty arguments survive unchanged. Arguments passed to `docker run` replace the upstream `CMD`. CI builds from the exact upstream digest it inspected.

## Automated Builds

GitHub Actions automatically:
- Checks daily for upstream image updates
- **Detects significant changes** (entrypoint/command modifications) and alerts
- **Tests images before promotion** using comprehensive test suite
- Only rebuilds when upstream changes to avoid unnecessary churn
- Publishes to `ghcr.io/sibest19/octoeverywhere` with cascading semver tags that
  mirror the upstream version (e.g. upstream `5.0.2` produces):
  - `latest` - Current stable version (tested)
  - `5` - Latest release of that major version
  - `5.0` - Latest release of that major.minor version
  - `5.0.2` - This exact version
  Nothing is pushed to the registry until the AMD64 test suite passes. The
  release build uses the same upstream digest for AMD64 and ARM64.

### Resilience Features

- **Pre-deployment testing**: All images are tested before being tagged as `latest`
- **Change detection**: Alerts when upstream makes significant changes that might break compatibility
- **Emergency rollback**: Manual workflow to quickly revert to previous version
- **Health monitoring**: Standalone script for continuous monitoring (`health-check.sh`)

## Emergency Rollback

If something breaks, quickly revert to a previous version:

**Option 1: Use a specific version**
```bash
docker pull ghcr.io/sibest19/octoeverywhere:5.0.1
```

**Option 2: Automated rollback**
Go to Actions → Emergency Rollback → Run workflow, then select the target version. The workflow requires both AMD64 and ARM64 in the target image and preserves the complete image index in both the backup and `latest` tags.

Scheduled builds skip the withdrawn upstream digest and resume when upstream publishes a different digest. A push to `main` or a manual build overrides the hold. If the withdrawn image has no upstream digest recorded, scheduled publishing stays paused until an explicit build.

### Health Monitoring

Run the included health check script:
```bash
./health-check.sh
```

Set environment variables for alerts:
```bash
export TELEGRAM_BOT_TOKEN="your_bot_token"
export TELEGRAM_CHAT_ID="your_chat_id"
./health-check.sh
```

### Testing Changes

Test the wrapper locally (requires Docker and `jq` on the host):
```bash
./test-wrapper.sh ghcr.io/sibest19/octoeverywhere:latest
```

The suite exercises the real entrypoint, argument preservation, user/group mapping, recursive data ownership, rejected IDs, read-only data, invalid configuration, and application startup with an unreachable Klipper printer.

## Contributing

1. Fork the repository.
2. Create a feature branch (`git checkout -b my-feature`).
3. Commit your changes and push (`git push origin my-feature`).
4. Open a Pull Request describing your change.

Please ensure any additions keep the wrapper minimal and continue to leverage the upstream image.

---

Created and maintained by Simone Andreani ([@sibest19](https://github.com/sibest19)). Feel free to open issues or PRs for improvements.
