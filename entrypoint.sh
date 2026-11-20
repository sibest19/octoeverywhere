#!/bin/sh
set -eu

PUID=${PUID-1001}
PGID=${PGID-0}

for value in "$PUID" "$PGID"; do
  case "$value" in
  '' | *[!0-9]* | 0[0-9]*)
    echo "[ERROR] PUID and PGID must be non-negative decimal integers without leading zeros" >&2
    exit 1
    ;;
  esac
  if ! [ "$value" -le 4294967294 ]; then
    echo "[ERROR] PUID and PGID must be at most 4294967294" >&2
    exit 1
  fi
done

if [ "$PUID" = 0 ]; then
  echo "[ERROR] PUID must be nonzero" >&2
  exit 1
fi

if ! getent group "$PGID" >/dev/null 2>&1; then
  addgroup -g "$PGID" appgroup
fi

if ! getent passwd "$PUID" >/dev/null 2>&1; then
  adduser -D -H -u "$PUID" -G "$(getent group "$PGID" | cut -d: -f1)" appuser
fi

echo "[INFO] Setting ownership of /data to ${PUID}:${PGID}"
chown -R "${PUID}:${PGID}" /data || {
  echo "[ERROR] Cannot set /data ownership; check mount permissions" >&2
  exit 1
}

# Keep JSON arguments intact and replace PID 1 so signals reach the upstream process.
exec su-exec "${PUID}:${PGID}" python3 -c '
import json
import os
import sys

with open("/upstream_config.json") as config_file:
    config = json.load(config_file)
for key in ("entrypoint", "cmd"):
    value = config[key]
    if value is not None and (
        not isinstance(value, list)
        or not all(isinstance(arg, str) and "\0" not in arg for arg in value)
    ):
        sys.exit(f"[ERROR] Invalid upstream {key}: expected an array of strings or null")
argv = (config["entrypoint"] or []) + (sys.argv[1:] or config["cmd"] or [])
if not argv or not argv[0]:
    sys.exit("[ERROR] Upstream command is empty")
os.execvp(argv[0], argv)
' "$@"
