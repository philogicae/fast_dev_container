#!/usr/bin/env bash
set -e

# Directories
WORKSPACE_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${WORKSPACE_DIR}/project"
mkdir -p "${PROJECT_DIR}"

#################################### Configuration variables - modify these as needed ####################################
CONTAINER_NAME="__PROJECT__"
DOCKER_CMD=""                           # Container runtime (default: docker)
IMAGE=""                                # Docker image or Dockerfile path (overrides default image or ./fdevc.Dockerfile)
SOCKET="true"                           # Mount Docker socket (true/false)
PERSIST="false"                         # Keep container running on exit (true/false)
FORCE="false"                           # Force container creation (true/false)
PORTS=""                                # Docker ports (e.g. "8080:80 443")
STARTUP_CMD="./fdevc_setup/runnable.sh" # Startup script auto-mounted into /workspace/fdevc_setup
VOLUMES=( # Additional volumes ("/data:/data" "virtual:/local")
	"${WORKSPACE_DIR}/fdevc_setup:/workspace/fdevc_setup" # fdevc_setup
	"${PROJECT_DIR}:/workspace/project")                  # Working directory
EXCLUDED=()                                            # Excluded volumes ("/workspace/project/node_modules")
##########################################################################################################################

# Resolve fdevc command invocation
FDEVC="${FDEVC:-${HOME}/.fdevc/fdevc.sh}"
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

# Build fdevc arguments
FDEVC_ARGS=()
[ -n "$DOCKER_CMD" ] && FDEVC_ARGS+=(--dkr "$DOCKER_CMD")
[ -n "$IMAGE" ] && FDEVC_ARGS+=(-i "$IMAGE")
[ "$SOCKET" != "true" ] && FDEVC_ARGS+=(--no-s)
[ "$PERSIST" = "true" ] && FDEVC_ARGS+=(-d) || FDEVC_ARGS+=(--no-d)
[ "$FORCE" = "true" ] && FDEVC_ARGS+=(-f)
[ -n "$PORTS" ] && FDEVC_ARGS+=(-p "$PORTS")
[ -n "$STARTUP_CMD" ] && FDEVC_ARGS+=(--c-s "$STARTUP_CMD")

# Don't mount root directory
FDEVC_ARGS+=(--no-v-dir)

# Add custom volumes
for vol in "${VOLUMES[@]}"; do
	[ -n "$vol" ] && FDEVC_ARGS+=(-v "$vol")
done

# Add excluded volumes
for excl in "${EXCLUDED[@]}"; do
	[ -n "$excl" ] && FDEVC_ARGS+=(-v "$excl")
done

# Resolve container name
CONTAINER_ARG=""
if [ -n "$CONTAINER_NAME" ]; then
	ACTUAL_NAME="$CONTAINER_NAME"
	[ "$CONTAINER_NAME" = "__PROJECT__" ] && ACTUAL_NAME="$(basename "$PWD")"
	# Check if container exists
	DOCKER_CHECK="${DOCKER_CMD:-${FDEVC_DOCKER:-docker}}"
	read -ra DOCKER_PARTS <<<"$DOCKER_CHECK"
	if "${DOCKER_PARTS[@]}" ps -a --filter "name=^fdevc.${ACTUAL_NAME}$" --format '{{.Names}}' 2>/dev/null | grep -q "^fdevc.${ACTUAL_NAME}$"; then
		CONTAINER_ARG="fdevc.${ACTUAL_NAME}"
	else
		FDEVC_ARGS+=(-n "$ACTUAL_NAME")
	fi
fi

# Launch container
echo "Launching container with fdevc"
[ -n "$CONTAINER_ARG" ] && FDEVC_ARGS+=("$CONTAINER_ARG")

if [ -n "$FDEVC_SOURCE" ]; then
	printf -v ARGS_QUOTED ' %q' "${FDEVC_ARGS[@]}"
	bash -lc "source '$FDEVC_SOURCE' && fdevc${ARGS_QUOTED}"
else
	"${FDEVC_CMD[@]}" "${FDEVC_ARGS[@]}"
fi
