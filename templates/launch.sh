#!/usr/bin/env bash
set -e

# Configuration variables - modify these as needed
FDEVC="${FDEVC:-${HOME}/.fdevc/fdevc.sh}"
CONTAINER_NAME="__PROJECT__"
IMAGE=""
PORTS=""
STARTUP_CMD="./runnable.sh"
PERSIST="false"
DOCKER_SOCKET="true"
FORCE="false"

# Resolve fdevc command invocation
FDEVC_CMD=()
FDEVC_SOURCE=""
if command -v fdevc >/dev/null 2>&1; then
    FDEVC_CMD+=(fdevc)
elif [ -f "$FDEVC" ]; then
    FDEVC_SOURCE="$FDEVC"
else
    echo "Error: could not locate fdevc command or script" >&2
    echo "Checked: 'fdevc' in PATH and '$FDEVC'" >&2
    exit 1
fi

# Build fdevc command arguments
FDEVC_ARGS=()
CONTAINER_ARG=""

# Determine container name handling
if [ -n "$CONTAINER_NAME" ]; then
    # Resolve actual container name
    ACTUAL_NAME="$CONTAINER_NAME"
    [ "$CONTAINER_NAME" = "__PROJECT__" ] && ACTUAL_NAME="$(basename "$PWD")"
    # Resolve docker command (split into array for multi-word commands like "docker -H host")
    DOCKER_CMD_STR="${FDEVC_DOCKER:-docker}"
    read -ra DOCKER_CMD_PARTS <<< "$DOCKER_CMD_STR"
    # Check if container already exists
    FULL_CONTAINER_NAME="fdevc.${ACTUAL_NAME}"
    if "${DOCKER_CMD_PARTS[@]}" ps -a --filter "name=^${FULL_CONTAINER_NAME}$" --format '{{.Names}}' 2>/dev/null | grep -q "^${FULL_CONTAINER_NAME}$"; then
        # Container exists, use as positional argument (reattach)
        CONTAINER_ARG="$FULL_CONTAINER_NAME"
    else
        # Container doesn't exist, use -n to create it
        FDEVC_ARGS+=(-n "$ACTUAL_NAME")
    fi
fi

# Add startup command
if [ -n "$STARTUP_CMD" ]; then
    FDEVC_ARGS+=(--c-s "$STARTUP_CMD")
fi

# Add image if specified
if [ -n "$IMAGE" ]; then
    FDEVC_ARGS+=(-i "$IMAGE")
fi

# Add ports if specified
if [ -n "$PORTS" ]; then
    FDEVC_ARGS+=(-p "$PORTS")
fi

# Disable volume mounting (no project path)
FDEVC_ARGS+=(--no-v)

# Configure socket
if [ "$DOCKER_SOCKET" != "true" ]; then
    FDEVC_ARGS+=(--no-s)
fi

# Configure persistence
if [ "$PERSIST" = "true" ]; then
    FDEVC_ARGS+=(-d)
else
    FDEVC_ARGS+=(--no-d)
fi

# Configure force
if [ "$FORCE" = "true" ]; then
    FDEVC_ARGS+=(-f)
fi

# Launch the container
echo "Launching container with fdevc..."
if [ -n "$FDEVC_SOURCE" ]; then
    # Source-based invocation (requires quoting for bash -lc)
    # shellcheck disable=SC1003
    printf -v FDEVC_ARGS_QUOTED ' %q' "${FDEVC_ARGS[@]}"
    CONTAINER_ARG_QUOTED=""
    [ -n "$CONTAINER_ARG" ] && printf -v CONTAINER_ARG_QUOTED ' %q' "$CONTAINER_ARG"
    bash -lc "source '$FDEVC_SOURCE' && fdevc${FDEVC_ARGS_QUOTED}${CONTAINER_ARG_QUOTED}"
else
    # Command-based invocation
    [ -n "$CONTAINER_ARG" ] && FDEVC_ARGS+=("$CONTAINER_ARG")
    "${FDEVC_CMD[@]}" "${FDEVC_ARGS[@]}"
fi