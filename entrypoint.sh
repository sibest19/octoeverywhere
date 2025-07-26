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
if [ ! -f "$PYTHON_PATH" ] || [ ! -x "$PYTHON_PATH" ]; then
  echo "[ERROR] Python executable not found at: $PYTHON_PATH"
  echo "[INFO] Available Python installations:"
  find /app -name "python*" -type f -executable 2>/dev/null || echo "No Python found in /app"
  find /usr -name "python*" -type f -executable 2>/dev/null | head -5 || echo "No system Python found"

  # Try virtual environment Python first (this has the required packages)
  if [ -d "/app/octoeverywhere-env" ]; then
    # Check for different Python executable names in the virtual environment
    for py_name in python python3 python3.12; do
      if [ -f "/app/octoeverywhere-env/bin/$py_name" ]; then
        echo "[INFO] Found virtual environment Python at /app/octoeverywhere-env/bin/$py_name"
        EXEC_CMD="/app/octoeverywhere-env/bin/$py_name -m docker_octoeverywhere"
        break
      fi
    done
  fi

  # If virtual environment Python not found, try system Python as last resort
  if [ "$PYTHON_PATH" = "$(echo "$EXEC_CMD" | awk '{print $1}')" ]; then
    if [ -f "/usr/bin/python3" ]; then
      echo "[WARN] Using system Python at /usr/bin/python3 - packages may be missing"
      EXEC_CMD="/usr/bin/python3 -m docker_octoeverywhere"
    elif [ -f "/usr/bin/python" ]; then
      echo "[WARN] Using system Python at /usr/bin/python - packages may be missing"
      EXEC_CMD="/usr/bin/python -m docker_octoeverywhere"
    fi
  fi
fi

echo "[DEBUG] Final command to execute: $EXEC_CMD"
echo "[DEBUG] Current working directory: $(pwd)"
echo "[DEBUG] Running as user: $(id)"

# Additional debug info for virtual environment
FINAL_PYTHON_PATH=$(echo "$EXEC_CMD" | awk '{print $1}')
if [ -f "$FINAL_PYTHON_PATH" ]; then
  echo "[DEBUG] Python executable exists at: $FINAL_PYTHON_PATH"
  echo "[DEBUG] Python version: $($FINAL_PYTHON_PATH --version 2>&1)"
  if echo "$FINAL_PYTHON_PATH" | grep -q "octoeverywhere-env"; then
    echo "[DEBUG] Using virtual environment Python - packages should be available"
    echo "[DEBUG] Virtual env site-packages: $(ls -la /app/octoeverywhere-env/lib/python*/site-packages/ 2>/dev/null | wc -l) items"
  else
    echo "[DEBUG] Using system Python - packages may be missing"
  fi
else
  echo "[ERROR] Final Python executable still not found: $FINAL_PYTHON_PATH"
fi

# Drop privileges and execute the discovered command
echo "[INFO] Executing: $EXEC_CMD"
exec su-exec "${PUID}:${PGID}" sh -c "$EXEC_CMD"
