#!/bin/bash
set -euo pipefail

IMAGE_TAG=${1:-ghcr.io/sibest19/octoeverywhere:latest}
TEST_DIR=$(mktemp -d)
CONTAINER_NAME="test-octo-$$"
cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Each docker command must fail the suite if an assertion fails.
docker run --rm --entrypoint sh "$IMAGE_TAG" -ec '
  test -x /entrypoint.sh
  command -v su-exec
  command -v python3
  jq -e "(.entrypoint | type == \"array\" or . == null) and (.cmd | type == \"array\" or . == null)" /upstream_config.json
'

PROBE='import json, os, sys
assert os.getuid() == int(os.environ["PUID"])
assert os.getgid() == int(os.environ["PGID"])
assert os.getpid() == 1
assert sys.argv[1:] == json.loads(os.environ["EXPECTED_ARGS"]), sys.argv
for path in ("/data", "/data/root_file"):
    stat = os.stat(path)
    assert stat.st_uid == os.getuid() and stat.st_gid == os.getgid()
with open("/data/writable", "w") as output:
    output.write("ok")
assert not os.path.exists("/data/injected")
print("Entrypoint, arguments and permissions: PASSED")'
# shellcheck disable=SC2016 # Shell syntax is a literal test argument.
ARGS='["argument with spaces", "", "\"quotes\"", "$(touch /data/injected)", "line\nbreak"]'
jq -n --arg probe "$PROBE" --argjson args "$ARGS" \
  '{entrypoint: ["python3", "-c", $probe], cmd: $args}' >"$TEST_DIR/config.json"

for ids in 1000:1000 1001:0 1001:1001; do
  docker run --rm --tmpfs /data \
    -e PUID="${ids%:*}" -e PGID="${ids#*:}" -e EXPECTED_ARGS="$ARGS" \
    -v "$TEST_DIR/config.json:/upstream_config.json:ro" \
    --entrypoint sh "$IMAGE_TAG" -ec 'touch /data/root_file; exec /entrypoint.sh'
done

# Runtime arguments replace CMD and are appended to ENTRYPOINT.
docker run --rm --tmpfs /data \
  -e PUID=1000 -e PGID=1000 -e EXPECTED_ARGS='["replacement argument", ""]' \
  -v "$TEST_DIR/config.json:/upstream_config.json:ro" \
  --entrypoint sh "$IMAGE_TAG" -ec 'touch /data/root_file; exec /entrypoint.sh "$@"' sh 'replacement argument' ''

# A CMD-only image must also work.
jq '.cmd = (.entrypoint + .cmd) | .entrypoint = null' "$TEST_DIR/config.json" >"$TEST_DIR/cmd-only.json"
docker run --rm --tmpfs /data \
  -e PUID=1000 -e PGID=1000 -e EXPECTED_ARGS="$ARGS" \
  -v "$TEST_DIR/cmd-only.json:/upstream_config.json:ro" \
  --entrypoint sh "$IMAGE_TAG" -ec 'touch /data/root_file; exec /entrypoint.sh'

expect_failure() {
  local message=$1
  shift
  if docker run --rm "$@" "$IMAGE_TAG" >"$TEST_DIR/failure.log" 2>&1; then
    echo "Expected failure: $message" >&2
    exit 1
  fi
  cat "$TEST_DIR/failure.log"
  grep -F "$message" "$TEST_DIR/failure.log"
}

for variable in PUID PGID; do
  for value in '' invalid -1 01 4294967295; do
    expect_failure '[ERROR] PUID and PGID must be' --tmpfs /data -e "$variable=$value"
  done
done

expect_failure '[ERROR] PUID must be nonzero' --tmpfs /data -e PUID=0

mkdir "$TEST_DIR/read-only"
expect_failure '[ERROR] Cannot set /data ownership' \
  -e PUID=1000 -e PGID=1000 -v "$TEST_DIR/read-only:/data:ro"

printf '%s\n' '{"entrypoint": "invalid", "cmd": null}' >"$TEST_DIR/invalid.json"
expect_failure '[ERROR] Invalid upstream entrypoint' --tmpfs /data \
  -v "$TEST_DIR/invalid.json:/upstream_config.json:ro"
printf '%s\n' '{"entrypoint": null, "cmd": null}' >"$TEST_DIR/empty.json"
expect_failure '[ERROR] Upstream command is empty' --tmpfs /data \
  -v "$TEST_DIR/empty.json:/upstream_config.json:ro"

# Use a supported mode: the real application should retry an unreachable printer.
docker run -d --name "$CONTAINER_NAME" --tmpfs /data \
  -e PUID=1000 -e PGID=1000 -e COMPANION_MODE=klipper -e PRINTER_IP=127.0.0.1 "$IMAGE_TAG"
sleep 5
if [ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME")" != true ]; then
  docker logs "$CONTAINER_NAME"
  exit 1
fi

docker stop --time 5 "$CONTAINER_NAME" >/dev/null
if [ "$(docker inspect --format '{{.State.ExitCode}}' "$CONTAINER_NAME")" != 0 ]; then
  docker logs "$CONTAINER_NAME"
  echo 'Container did not shut down cleanly' >&2
  exit 1
fi

echo 'All wrapper tests PASSED'
