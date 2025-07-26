#!/bin/sh

# Fallback to image's original UID/GID if not set
PUID=${PUID:-1001}
PGID=${PGID:-0}

echo "[INFO] Running as root. Dropping to UID=${PUID}, GID=${PGID}"

# Fix ownership of /data if needed
chown -R "${PUID}:${PGID}" /data

# Load the upstream configuration discovered during build
if [ -f "/upstream_config" ]; then
    . /upstream_config
    echo "[INFO] Loaded upstream config from build time"
    echo "[INFO] UPSTREAM_ENTRYPOINT: $UPSTREAM_ENTRYPOINT"
    echo "[INFO] UPSTREAM_CMD: $UPSTREAM_CMD"
else
    echo "[WARN] No upstream config found, using defaults"
    UPSTREAM_ENTRYPOINT='["/app/octoeverywhere-env/bin/python","-m","docker_octoeverywhere"]'
    UPSTREAM_CMD='null'
fi

# Parse the JSON arrays to extract the command
# Handle entrypoint (should be an array like ["/app/octoeverywhere-env/bin/python","-m","docker_octoeverywhere"])
if [ "$UPSTREAM_ENTRYPOINT" != "null" ] && [ -n "$UPSTREAM_ENTRYPOINT" ]; then
    # Extract command from JSON array format
    EXEC_CMD=$(echo "$UPSTREAM_ENTRYPOINT" | jq -r 'join(" ")' 2>/dev/null || echo "$UPSTREAM_ENTRYPOINT")
    echo "[INFO] Using upstream entrypoint: $EXEC_CMD"
elif [ "$UPSTREAM_CMD" != "null" ] && [ -n "$UPSTREAM_CMD" ]; then
    # Fallback to CMD if entrypoint is null
    EXEC_CMD=$(echo "$UPSTREAM_CMD" | jq -r 'join(" ")' 2>/dev/null || echo "$UPSTREAM_CMD")
    echo "[INFO] Using upstream cmd: $EXEC_CMD"
else
    # Final fallback to known working command
    EXEC_CMD="/app/octoeverywhere-env/bin/python -m docker_octoeverywhere"
    echo "[INFO] Using fallback command: $EXEC_CMD"
fi

# Set working directory (upstream uses /app/octoeverywhere as WORKDIR)
cd /app/octoeverywhere 2>/dev/null || cd /app 2>/dev/null || true

# Drop privileges and execute the discovered command
echo "[INFO] Executing: $EXEC_CMD"
exec su-exec "${PUID}:${PGID}" sh -c "$EXEC_CMD"
