#!/bin/bash
# Health check script for OctoEverywhere wrapper
# Can be run as a cron job or monitoring system

set -e

IMAGE="${1:-ghcr.io/sibest19/octoeverywhere:latest}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}" # Set this environment variable
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"     # Set this environment variable

send_alert() {
  local message="$1"
  local severity="$2" # INFO, WARNING, ERROR

  echo "[$severity] $message"

  # Telegram notification
  if [[ -n "$TELEGRAM_BOT_TOKEN" ]] && [[ -n "$TELEGRAM_CHAT_ID" ]]; then
    local emoji=""
    case "$severity" in
    "ERROR") emoji="🚨" ;;
    "WARNING") emoji="⚠️" ;;
    "INFO") emoji="ℹ️" ;;
    esac

    local telegram_message
    telegram_message="${emoji} *OctoEverywhere Wrapper Alert*
        
*Severity:* ${severity}
*Time:* $(date)
*Message:* ${message}"

    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "text=${telegram_message}" \
      -d "parse_mode=Markdown" >/dev/null || true
  fi
}

check_image_availability() {
  echo "Checking image availability..."
  # First check if image exists locally
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "✅ Image available locally"
    return 0
  fi
  # If not local, try to pull it
  if ! docker pull "$IMAGE" >/dev/null 2>&1; then
    send_alert "Failed to pull image $IMAGE" "ERROR"
    return 1
  fi
  echo "✅ Image pull successful"
}

check_basic_functionality() {
  echo "Checking basic functionality..."

  if ! docker run --rm \
    -e PUID=1000 \
    -e PGID=1000 \
    --tmpfs /data \
    --entrypoint sh \
    "$IMAGE" \
    -ec '
      test -x /entrypoint.sh
      command -v su-exec
      command -v python3
      if [ -f /upstream_config.json ]; then
        jq -e "type == \"object\"" /upstream_config.json
      else
        test -s /upstream_config
      fi
    ' >/dev/null 2>&1; then

    send_alert "Basic functionality check failed for $IMAGE" "ERROR"
    return 1
  fi
  echo "✅ Basic functionality check passed"
}

check_upstream_changes() {
  echo "Checking for significant upstream changes..."

  local upstream_entrypoint upstream_cmd wrapper_config
  wrapper_config=$(docker run --rm --entrypoint sh "$IMAGE" -ec '
    if [ -f /upstream_config.json ]; then
      cat /upstream_config.json
    else
      test -s /upstream_config
    fi
  ') || return 1
  if [ -z "$wrapper_config" ]; then
    echo "Legacy image: skipping upstream configuration comparison"
    return 0
  fi

  docker pull octoeverywhere/octoeverywhere:latest >/dev/null 2>&1 || return 1
  upstream_entrypoint=$(docker image inspect octoeverywhere/octoeverywhere:latest --format='{{json .Config.Entrypoint}}') || return 1
  upstream_cmd=$(docker image inspect octoeverywhere/octoeverywhere:latest --format='{{json .Config.Cmd}}') || return 1

  if ! echo "$wrapper_config" | jq -e --argjson entrypoint "$upstream_entrypoint" --argjson cmd "$upstream_cmd" \
    '.entrypoint == $entrypoint and .cmd == $cmd' >/dev/null; then
    send_alert "Image configuration differs from current upstream; this is expected after a rollback." "WARNING"
    return 0
  fi
  echo "✅ Upstream configuration matches"
}

check_container_startup() {
  echo "Checking container startup..."
  local container_name="health-check-$$"
  trap 'docker rm -f "$container_name" >/dev/null 2>&1 || true' RETURN

  # Start container in background - use tmpfs instead of bind mount to avoid permission issues
  if ! docker run -d \
    --name "$container_name" \
    -e PUID=1000 \
    -e PGID=1000 \
    -e COMPANION_MODE=klipper \
    -e PRINTER_IP=127.0.0.1 \
    --tmpfs /data \
    "$IMAGE" >/dev/null 2>&1; then

    send_alert "Failed to start container for health check" "ERROR"
    return 1
  fi

  # Wait a few seconds and check if still running
  sleep 5
  if [ "$(docker inspect --format '{{.State.Running}}' "$container_name")" != true ]; then
    local logs
    logs=$(docker logs "$container_name" 2>&1 | tail -10)
    send_alert "Container exited unexpectedly during health check.\\nLogs:\\n$logs" "ERROR"
    return 1
  fi

  echo "✅ Container startup check passed"
}

main() {
  echo "Starting OctoEverywhere wrapper health check..."
  echo "Image: $IMAGE"
  echo "Time: $(date)"
  echo "==========================================="

  local failed=0

  check_image_availability || failed=$((failed + 1))
  check_basic_functionality || failed=$((failed + 1))
  check_upstream_changes || failed=$((failed + 1))
  check_container_startup || failed=$((failed + 1))

  echo "==========================================="
  if [[ $failed -eq 0 ]]; then
    echo "✅ All health checks passed!"
    # send_alert "OctoEverywhere wrapper health check: All systems operational" "INFO"
  else
    echo "❌ $failed health check(s) failed!"
    send_alert "$failed health checks failed for OctoEverywhere wrapper" "ERROR"
    exit 1
  fi
}

main "$@"
