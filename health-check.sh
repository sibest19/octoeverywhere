#!/bin/bash
# Health check script for OctoEverywhere wrapper
# Can be run as a cron job or monitoring system

set -e

IMAGE="${1:-ghcr.io/sibest19/octoeverywhere:latest}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"  # Set this environment variable
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"      # Set this environment variable

send_alert() {
    local message="$1"
    local severity="$2"  # INFO, WARNING, ERROR
    
    echo "[$severity] $message"
    
    # Telegram notification
    if [[ -n "$TELEGRAM_BOT_TOKEN" ]] && [[ -n "$TELEGRAM_CHAT_ID" ]]; then
        local emoji=""
        case "$severity" in
            "ERROR") emoji="🚨" ;;
            "WARNING") emoji="⚠️" ;;
            "INFO") emoji="ℹ️" ;;
        esac
        
        local telegram_message="${emoji} *OctoEverywhere Wrapper Alert*
        
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
        --entrypoint="" \
        "$IMAGE" \
        sh -c "test -x /entrypoint.sh && which su-exec && which jq && test -f /upstream_config" >/dev/null 2>&1; then
        
        send_alert "Basic functionality check failed for $IMAGE" "ERROR"
        return 1
    fi
    echo "✅ Basic functionality check passed"
}

check_upstream_changes() {
    echo "Checking for significant upstream changes..."
    
    # Get current upstream image info
    docker pull octoeverywhere/octoeverywhere:latest >/dev/null 2>&1
    local upstream_entrypoint=$(docker image inspect octoeverywhere/octoeverywhere:latest --format='{{json .Config.Entrypoint}}')
    local upstream_cmd=$(docker image inspect octoeverywhere/octoeverywhere:latest --format='{{json .Config.Cmd}}')
    
    # Get our wrapper's stored config
    local wrapper_entrypoint=$(docker run --rm --entrypoint="" "$IMAGE" sh -c '. /upstream_config && echo "$UPSTREAM_ENTRYPOINT"')
    local wrapper_cmd=$(docker run --rm --entrypoint="" "$IMAGE" sh -c '. /upstream_config && echo "$UPSTREAM_CMD"')
    
    # Normalize both for comparison by parsing as JSON arrays
    local upstream_norm=$(echo "$upstream_entrypoint" | jq -r 'join(" ")' 2>/dev/null || echo "$upstream_entrypoint")
    local wrapper_norm
    if echo "$wrapper_entrypoint" | grep -q '^\[.*\]$'; then
        # Convert [/path,-m,module] format to "/path" "-m" "module" and then parse
        wrapper_entrypoint_json=$(echo "$wrapper_entrypoint" | sed 's/\[/["/; s/\]/"]/' | sed 's/,/","/g')
        wrapper_norm=$(echo "$wrapper_entrypoint_json" | jq -r 'join(" ")' 2>/dev/null || echo "$wrapper_entrypoint")
    else
        wrapper_norm="$wrapper_entrypoint"
    fi
    
    if [[ "$upstream_norm" != "$wrapper_norm" ]] || [[ "$upstream_cmd" != "$wrapper_cmd" ]]; then
        send_alert "Upstream configuration mismatch detected! Wrapper may be outdated.\\nUpstream: $upstream_norm\\nWrapper: $wrapper_norm" "WARNING"
        return 1
    fi
    echo "✅ Upstream configuration matches"
}

check_container_startup() {
    echo "Checking container startup..."
    local container_name="health-check-$$"
    trap "docker stop '$container_name' 2>/dev/null || true; docker rm '$container_name' 2>/dev/null || true" RETURN
    
    # Start container in background - use tmpfs instead of bind mount to avoid permission issues
    if ! docker run -d \
        --name "$container_name" \
        -e PUID=1000 \
        -e PGID=1000 \
        -e COMPANION_MODE=test \
        -e SERIAL_NUMBER=test \
        -e ACCESS_CODE=test \
        -e PRINTER_IP=127.0.0.1 \
        --tmpfs /data \
        "$IMAGE" >/dev/null 2>&1; then
        
        send_alert "Failed to start container for health check" "ERROR"  
        return 1
    fi
    
    # Wait a few seconds and check if still running
    sleep 5
    if ! docker ps | grep -q "$container_name"; then
        local logs=$(docker logs "$container_name" 2>&1 | tail -10)
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
    
    check_image_availability || ((failed++))
    check_basic_functionality || ((failed++))
    check_upstream_changes || ((failed++))
    check_container_startup || ((failed++))
    
    echo "==========================================="
    if [[ $failed -eq 0 ]]; then
        echo "✅ All health checks passed!"
        send_alert "OctoEverywhere wrapper health check: All systems operational" "INFO"
    else
        echo "❌ $failed health check(s) failed!"
        send_alert "$failed health checks failed for OctoEverywhere wrapper" "ERROR"
        exit 1
    fi
}

main "$@"
