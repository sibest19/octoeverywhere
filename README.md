# OctoEverywhere Non-Root Wrapper Image

[![Build and Push to GHCR](https://github.com/sibest19/octoeverywhere/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/sibest19/octoeverywhere/actions/workflows/build-and-push.yml)
[![GitHub Container Registry](https://img.shields.io/badge/ghcr.io-sibest19%2Foctoeverywhere-blue?logo=docker)](https://github.com/sibest19/octoeverywhere/pkgs/container/octoeverywhere)
[![Docker Pulls](https://img.shields.io/badge/dynamic/json?color=blue&label=pulls&query=$.download_count&url=https%3A%2F%2Fghcr.io%2Fv2%2Fsibest19%2Foctoeverywhere%2Fblobs%2Fsha256%3Amanifest&logo=docker)](https://github.com/sibest19/octoeverywhere/pkgs/container/octoeverywhere)

This repository provides a minimal Docker wrapper around the official `octoeverywhere/octoeverywhere` image, adding dynamic user and group ID (PUID/PGID) support and automated builds via GitHub Actions. The goal is to allow running OctoEverywhere with the correct host-side file permissions without modifying the upstream image.

## Motivation

* **Avoid root-owned files**: The official image runs as a fixed user (UID 1001, GID 0), which can lead to permission issues when mounting host volumes with different ownership.
* **No custom image maintenance**: Instead of forking and maintaining a full custom build, this wrapper injects a small entrypoint script to drop privileges at runtime based on environment variables.
* **Automated builds**: Using GitHub Actions and GitHub Container Registry (GHCR), the wrapper image is rebuilt and published automatically whenever upstream or this repository is updated.

## Features

* **Dynamic PUID/PGID**: Set `PUID` and `PGID` environment variables to match any host user without rebuilding the image.
* **Runtime ownership fix**: On container start, the entrypoint script fixes ownership of `/data` and then drops privileges to the specified UID/GID.
* **Zero-image maintenance**: Leverages the official OctoEverywhere image as the base, preserving all upstream improvements and updates.
* **Smart upstream monitoring**: GitHub Actions workflow monitors the upstream image for changes and only rebuilds when necessary, rather than nightly builds.
* **Multi-tag support**: Publishes both `latest` and version-specific tags based on upstream image metadata.
* **Dynamic entrypoint discovery**: Automatically inspects and adapts to the upstream image's actual entrypoint and command configuration at build time, ensuring compatibility with any upstream changes.

## Repository Structure

```text
sibest19/octoeverywhere/
├── Dockerfile               # Extends the official image and installs su-exec
├── entrypoint.sh            # Privilege-dropping wrapper script
└── .github/
    └── workflows/
        └── build-and-push.yml  # GH Actions workflow for CI/CD
```

## Usage

1. **Pull and run** using Docker Compose or Docker CLI:

   ```yaml
   services:
     octoeverywhere:
       image: ghcr.io/sibest19/octoeverywhere:latest  # or use a specific version tag
       environment:
         - PUID=3023                   # Your host user ID
         - PGID=3023                   # Your host group ID
         - COMPANION_MODE=elegoo
         - PRINTER_IP=XXX.XXX.XXX.XXX  # Replace with your printer's IP
       volumes:
         - /mnt/data/octoeverywhere/elegoo-centauri-carbon-1:/data
       restart: unless-stopped
   ```

2. **Without Docker Compose**:

   ```bash
   docker run -d \
     -e PUID=$(id -u) \
     -e PGID=$(id -g) \
     -e COMPANION_MODE=elegoo \
     -e PRINTER_IP=XXX.XXX.XXX.XXX \
     -v /mnt/data/octoeverywhere/elegoo-centauri-carbon-1:/data \
     ghcr.io/sibest19/octoeverywhere:latest
   ```

## Configuration

* `PUID` and `PGID`: User and group IDs into which the container will drop privileges. Defaults to `1001` (upstream app user) and `0` (root group).
* `COMPANION_MODE`: Mode for OctoEverywhere (e.g., `elegoo`).
* `PRINTER_IP`: IP address of your printer on the local network.

## Upstream Compatibility

This wrapper is designed to be fully compatible with the official `octoeverywhere/octoeverywhere` image structure:

* **Base**: Alpine Linux with Python 3 virtualenv at `/app/octoeverywhere-env/`
* **Application**: Python module `docker_octoeverywhere` in working directory `/app/octoeverywhere/`
* **Data**: Persistent data stored in `/data/` (must be mounted by user)
* **User**: Runs as UID 1001, GID 0 by default (matching upstream)

### Dynamic Discovery

The wrapper uses `docker image inspect` during the build process to automatically discover the upstream image's actual entrypoint and command configuration. This information is stored in the wrapper image and used at runtime to execute the exact same command as the upstream image, but with dropped privileges.

**Build-time discovery:**
- Inspects upstream image: `docker image inspect octoeverywhere/octoeverywhere:latest`
- Extracts entrypoint and cmd: `--format='{{json .Config.Entrypoint}}'`
- Stores configuration in wrapper image for runtime use

**Runtime execution:**
- Loads discovered upstream configuration
- Parses JSON arrays (e.g., `["/app/octoeverywhere-env/bin/python","-m","docker_octoeverywhere"]`)
- Executes via `su-exec` with specified PUID/PGID

This approach ensures the wrapper remains compatible even if the upstream image changes its entrypoint or command structure.

## CI/CD Workflow

The workflow in `.github/workflows/build-and-push.yml`:

* **Smart Triggers**: 
  - On push to `main` branch
  - Daily check for upstream image updates (06:00 UTC)
  - Manual workflow dispatch for immediate builds
* **Dynamic Upstream Discovery**: 
  - Pulls and inspects upstream image with `docker image inspect`
  - Extracts actual entrypoint and command configuration
  - Passes discovered config as build arguments to ensure runtime compatibility
* **Upstream Monitoring**: Compares upstream image digest to detect actual changes, avoiding unnecessary rebuilds
* **Multi-tag Publishing**: 
  - `latest` tag for the most recent build
  - Version-specific tags based on upstream image metadata
* **Rich Build Metadata**: Stores upstream digest, version, entrypoint, and command info as image annotations
* **Efficient Builds**: Only rebuilds when upstream changes are detected or manual triggers occur

## Contributing

1. Fork the repository.
2. Create a feature branch (`git checkout -b my-feature`).
3. Commit your changes and push (`git push origin my-feature`).
4. Open a Pull Request describing your change.

Please ensure any additions keep the wrapper minimal and continue to leverage the upstream image.

---

Created and maintained by Simone Andreani ([@sibest19](https://github.com/sibest19)). Feel free to open issues or PRs for improvements.
