#!/bin/sh

# Fallback to image's original UID/GID if not set
PUID=${PUID:-1001}
PGID=${PGID:-0}

echo "[INFO] Running as root. Dropping to UID=${PUID}, GID=${PGID}"

# Create group if it doesn't exist
if ! getent group $PGID >/dev/null 2>&1; then
    echo "[INFO] Creating group with GID=${PGID}"
    addgroup -g $PGID appgroup
else
    echo "[INFO] Group with GID=${PGID} already exists"
fi

# Create user if it doesn't exist
if ! getent passwd $PUID >/dev/null 2>&1; then
    echo "[INFO] Creating user with UID=${PUID}"
    adduser -D -H -u $PUID -G $(getent group $PGID | cut -d: -f1) appuser
else
    echo "[INFO] User with UID=${PUID} already exists"
fi

# Fix ownership of /data directory
echo "[INFO] Setting ownership of /data to ${PUID}:${PGID}"
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
    echo "[INFO] Using upstream entrypoint: $UPSTREAM_ENTRYPOINT"
    # Check if it's a JSON array format
    if echo "$UPSTREAM_ENTRYPOINT" | grep -q '^\[.*\]$'; then
        # Extract command from JSON array format
        EXEC_CMD=$(echo "$UPSTREAM_ENTRYPOINT" | jq -r '.[]' 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
        if [ -z "$EXEC_CMD" ]; then
            # Fallback parsing for malformed JSON
            EXEC_CMD=$(echo "$UPSTREAM_ENTRYPOINT" | sed 's/^\[//;s/\]$//;s/","/\" \"/g;s/"//g')
        fi
    else
        # Not JSON format, use as-is
        EXEC_CMD="$UPSTREAM_ENTRYPOINT"
    fi
elif [ "$UPSTREAM_CMD" != "null" ] && [ -n "$UPSTREAM_CMD" ]; then
    echo "[INFO] Using upstream cmd: $UPSTREAM_CMD"
    # Check if it's a JSON array format
    if echo "$UPSTREAM_CMD" | grep -q '^\[.*\]$'; then
        # Extract command from JSON array format
        EXEC_CMD=$(echo "$UPSTREAM_CMD" | jq -r '.[]' 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
        if [ -z "$EXEC_CMD" ]; then
            # Fallback parsing for malformed JSON
            EXEC_CMD=$(echo "$UPSTREAM_CMD" | sed 's/^\[//;s/\]$//;s/","/\" \"/g;s/"//g')
        fi
    else
        # Not JSON format, use as-is
        EXEC_CMD="$UPSTREAM_CMD"
    fi
else
    # Final fallback to known working command
    EXEC_CMD="/app/octoeverywhere-env/bin/python -m docker_octoeverywhere"
    echo "[INFO] Using fallback command: $EXEC_CMD"
fi

# Set working directory (upstream uses /app/octoeverywhere as WORKDIR)
cd /app/octoeverywhere 2>/dev/null || cd /app 2>/dev/null || true

# Debug: Check if the Python executable exists
PYTHON_PATH=$(echo "$EXEC_CMD" | awk '{print $1}')
if [ ! -f "$PYTHON_PATH" ] && [ ! -x "$PYTHON_PATH" ]; then
    echo "[ERROR] Python executable not found at: $PYTHON_PATH"
    echo "[INFO] Available Python installations:"
    find /app -name "python*" -type f -executable 2>/dev/null || echo "No Python found in /app"
    find /usr -name "python*" -type f -executable 2>/dev/null | head -5 || echo "No system Python found"
    
    # Try common Python locations
    if [ -f "/usr/bin/python3" ]; then
        echo "[INFO] Found system Python at /usr/bin/python3, using fallback command"
        EXEC_CMD="/usr/bin/python3 -m docker_octoeverywhere"
    elif [ -f "/usr/bin/python" ]; then
        echo "[INFO] Found system Python at /usr/bin/python, using fallback command"
        EXEC_CMD="/usr/bin/python -m docker_octoeverywhere"
    fi
fi

echo "[DEBUG] Final command to execute: $EXEC_CMD"
echo "[DEBUG] Current working directory: $(pwd)"
echo "[DEBUG] Running as user: $(id)"

# Drop privileges and execute the discovered command
echo "[INFO] Executing: $EXEC_CMD"
exec su-exec "${PUID}:${PGID}" sh -c "$EXEC_CMD"
