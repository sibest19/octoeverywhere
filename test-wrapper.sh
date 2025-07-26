#!/bin/bash
set -e

# Test script for the OctoEverywhere wrapper image
# Usage: ./test-wrapper.sh [image-tag]

IMAGE_TAG=${1:-"ghcr.io/sibest19/octoeverywhere:latest"}
TEST_DIR="$(mktemp -d)"
FAILED_TESTS=0

cleanup() {
  # Clean up docker containers first
  docker stop test-octo 2>/dev/null || true
  docker rm test-octo 2>/dev/null || true

  # Clean up test directory with better error handling
  if [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR" 2>/dev/null || sudo rm -rf "$TEST_DIR" 2>/dev/null || {
      log "Warning: Could not remove test directory $TEST_DIR"
    }
  fi
}
trap cleanup EXIT

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

test_basic_functionality() {
  log "Testing basic functionality..."

  # Test that the image can start and basic tools are present - use tmpfs for consistency
  docker run --rm \
    -e PUID=1000 \
    -e PGID=1000 \
    --tmpfs /data \
    --entrypoint="" \
    "$IMAGE_TAG" \
    sh -c "
            # Check required files and tools
            test -x /entrypoint.sh || (echo 'entrypoint.sh missing or not executable' && exit 1)
            which su-exec || (echo 'su-exec not installed' && exit 1)
            which jq || (echo 'jq not installed' && exit 1)
            test -f /upstream_config || (echo 'upstream_config missing' && exit 1)
            echo 'Basic functionality test: PASSED'
        " || {
    log "Basic functionality test: FAILED"
    ((FAILED_TESTS++))
  }
}

test_privilege_dropping() {
  log "Testing privilege dropping..."

  # Create a test file as root, then check if container can access it with correct permissions
  sudo touch "$TEST_DIR/root_file" 2>/dev/null || touch "$TEST_DIR/root_file"

  # Test that su-exec works and can drop privileges properly
  docker run --rm \
    -e PUID=1000 \
    -e PGID=1000 \
    -v "$TEST_DIR:/data" \
    --entrypoint="" \
    "$IMAGE_TAG" \
    sh -c "
            # Create user and group like the entrypoint does
            addgroup -g 1000 testgroup 2>/dev/null || true
            adduser -D -H -u 1000 -G testgroup testuser 2>/dev/null || true
            chown -R 1000:1000 /data
            
            # Test su-exec privilege dropping
            RESULT=\$(su-exec 1000:1000 sh -c 'id -u')
            test \"\$RESULT\" = \"1000\" || (echo 'UID test failed' && exit 1)
            
            RESULT=\$(su-exec 1000:1000 sh -c 'id -g')  
            test \"\$RESULT\" = \"1000\" || (echo 'GID test failed' && exit 1)
            
            # Test data directory access
            su-exec 1000:1000 sh -c 'test -w /data' || (echo 'Data access test failed' && exit 1)
            
            echo 'Privilege dropping test: PASSED'
        " || {
    log "Privilege dropping test: FAILED"
    ((FAILED_TESTS++))
  }
}

test_data_ownership() {
  log "Testing data directory ownership..."

  # Test that /data ownership can be properly set
  docker run --rm \
    -e PUID=1001 \
    -e PGID=1001 \
    -v "$TEST_DIR:/data" \
    --entrypoint="" \
    "$IMAGE_TAG" \
    sh -c "
            # Create user and group like the entrypoint does
            addgroup -g 1001 testgroup 2>/dev/null || true
            adduser -D -H -u 1001 -G testgroup testuser 2>/dev/null || true
            chown -R 1001:1001 /data
            
            # Test ownership as the target user
            su-exec 1001:1001 sh -c 'test -O /data && test -G /data' || exit 1
            echo 'Data ownership test: PASSED'
        " || {
    log "Data ownership test: FAILED"
    ((FAILED_TESTS++))
  }
}

test_upstream_config() {
  log "Testing upstream configuration..."

  docker run --rm \
    --entrypoint="" \
    "$IMAGE_TAG" \
    sh -c "
            . /upstream_config
            test -n \"\$UPSTREAM_ENTRYPOINT\" || (echo 'UPSTREAM_ENTRYPOINT not set' && exit 1)
            # Check if config looks like valid JSON or command
            echo \"\$UPSTREAM_ENTRYPOINT\" | grep -E '^\[.*\]$|^/|^python' || (echo 'UPSTREAM_ENTRYPOINT format invalid' && exit 1)
            echo 'Upstream config test: PASSED'
        " || {
    log "Upstream config test: FAILED"
    ((FAILED_TESTS++))
  }
}

test_container_startup() {
  log "Testing full container startup (5 second timeout)..."

  # Test that the container can start without immediate crashes - use tmpfs for consistency
  docker run -d \
    --name test-octo \
    -e PUID=1000 \
    -e PGID=1000 \
    -e COMPANION_MODE=test \
    -e SERIAL_NUMBER=test \
    -e ACCESS_CODE=test \
    -e PRINTER_IP=127.0.0.1 \
    --tmpfs /data \
    "$IMAGE_TAG" || {
    log "Container startup test: FAILED"
    ((FAILED_TESTS++))
    return
  }

  # Wait a moment and check if container is still running
  sleep 5

  if docker ps | grep -q test-octo; then
    log "Container startup test: PASSED"
  else
    log "Container startup test: FAILED (container exited)"
    log "Container logs:"
    docker logs test-octo
    ((FAILED_TESTS++))
  fi

  docker stop test-octo 2>/dev/null || true
  docker rm test-octo 2>/dev/null || true
}

# Run all tests
log "Starting wrapper image tests for: $IMAGE_TAG"
log "Test directory: $TEST_DIR"

test_basic_functionality
test_privilege_dropping
test_data_ownership
test_upstream_config
test_container_startup

# Summary
log "============================================"
if [ $FAILED_TESTS -eq 0 ]; then
  log "All tests PASSED! ✅"
  exit 0
else
  log "$FAILED_TESTS test(s) FAILED! ❌"
  exit 1
fi
