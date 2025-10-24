: "${FAST_DEV_CONTAINER_PYTHON:=python3}"
: "${FAST_DEV_CONTAINER_DOCKER:=docker}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
: "${FAST_DEV_CONTAINER_IMAGE:=${SCRIPT_DIR}/Dockerfile}"
CONFIG_FILE="${SCRIPT_DIR}/.dev_config.json"
UTILS_PY="${SCRIPT_DIR}/utils.py"
HELP_FILE="${SCRIPT_DIR}/help.txt"

_check_dependencies() {
    local missing=()
    local docker_base_cmd=$(echo "${FAST_DEV_CONTAINER_DOCKER}" | awk '{print $1}')
    if ! command -v "${docker_base_cmd}" &>/dev/null; then missing+=("${docker_base_cmd}"); fi
    if ! command -v "${FAST_DEV_CONTAINER_PYTHON}" &>/dev/null; then missing+=("${FAST_DEV_CONTAINER_PYTHON}"); fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "✗ Missing required dependencies: ${missing[*]}" >&2
        echo "  Please install them before using dev container commands." >&2
        return 1
    fi
    # Check if utils.py exists
    if [[ ! -f "${UTILS_PY}" ]]; then
        echo "✗ Missing utils.py at: ${UTILS_PY}" >&2
        return 1
    fi
    # Check if help.txt exists
    if [[ ! -f "${HELP_FILE}" ]]; then
        echo "✗ Missing help.txt at: ${HELP_FILE}" >&2
        return 1
    fi
}

if ! _check_dependencies; then return 1 2>/dev/null || exit 1; fi

_docker_exec() { local docker_cmd="$1"; shift; "${docker_cmd}" "$@"; }
_get_container_name() { echo "dev_$(basename "$PWD")"; }
_container_exists() {
    _docker_exec "${2:-${FAST_DEV_CONTAINER_DOCKER}}" ps -a --filter "name=^$1$" --format '{{.Names}}' 2>/dev/null | grep -q "^$1$"
}
_get_container_by_index() {
    _docker_exec "${FAST_DEV_CONTAINER_DOCKER}" ps -a --filter "name=^dev_" --format '{{.Names}}' 2>/dev/null | sed -n "$1p"
}

_load_config() {
    local container_name="$1"
    [[ ! -f "${CONFIG_FILE}" ]] && echo "{}" && return
    ${FAST_DEV_CONTAINER_PYTHON} "${UTILS_PY}" load_config "${CONFIG_FILE}" "${container_name}" 2>/dev/null
}

_get_config_value() {
    local config="$1" key="$2" default="$3"
    local value=$(echo "${config}" | ${FAST_DEV_CONTAINER_PYTHON} "${UTILS_PY}" get_config_value "${key}" "${default}" 2>/dev/null)
    echo "${value:-${default}}"
}

_get_config() {
    local container_name="$1"
    local key="$2"
    local config=$(_load_config "${container_name}")
    _get_config_value "${config}" "${key}"
}

_save_config() {
    local container_name="$1"
    local ports="$2"
    local image="$3"
    local docker_cmd="$4"
    local project_path="${5:-$PWD}"
    
    mkdir -p "$(dirname "${CONFIG_FILE}")"
    ${FAST_DEV_CONTAINER_PYTHON} "${UTILS_PY}" save_config "${CONFIG_FILE}" "${container_name}" "${ports}" "${image}" "${docker_cmd}" "${project_path}" 2>/dev/null
}

_remove_config() {
    local container_name="$1"
    [[ ! -f "${CONFIG_FILE}" ]] && return 0
    ${FAST_DEV_CONTAINER_PYTHON} "${UTILS_PY}" remove_config "${CONFIG_FILE}" "${container_name}" 2>/dev/null
}

_build_port_flags() {
    [[ -z "$1" ]] && return 0
    # Use tr to split by spaces, works in both bash and zsh
    echo "$1" | tr ' ' '\n' | while read -r port; do
        [[ -z "$port" ]] && continue
        echo "-p"
        if [[ "${port}" == *:* ]]; then
            echo "${port}"
        else
            echo "${port}:${port}"
        fi
    done
}

_is_dockerfile() { [[ -f "$1" ]] && return 0; return 1; }
_absolute_path() {
    local path="$1"
    if [[ "${path}" == /* ]]; then
        echo "${path}"
    else
        echo "$(cd "$(dirname "${path}")" 2>/dev/null && pwd)/$(basename "${path}")"
    fi
}

_build_from_dockerfile() {
    local dockerfile="$1" docker_cmd="${2:-${FAST_DEV_CONTAINER_DOCKER}}" container_name="${3:-dev_custom}"
    if [[ ! -f "${dockerfile}" ]]; then
        echo "✗ Dockerfile not found: ${dockerfile}" >&2
        return 1
    fi
    # Cross-platform hash computation (Linux uses md5sum, macOS uses md5)
    local dockerfile_hash
    if command -v md5sum &>/dev/null; then
        dockerfile_hash=$(md5sum "${dockerfile}" 2>/dev/null | cut -d' ' -f1 || echo "latest")
    elif command -v md5 &>/dev/null; then
        dockerfile_hash=$(md5 -q "${dockerfile}" 2>/dev/null || echo "latest")
    else
        dockerfile_hash="latest"
    fi
    local image_name="${container_name}:${dockerfile_hash:0:8}"
    local dockerfile_dir=$(dirname "${dockerfile}")
    if _docker_exec "${docker_cmd}" images -q "${image_name}" 2>/dev/null | grep -q .; then
        echo "→ Using cached image: ${image_name}" >&2
        echo "${image_name}"
        return 0
    fi
    echo "→ Building image from Dockerfile: ${dockerfile}" >&2
    echo "  Image tag: ${image_name}" >&2
    echo "  Building..." >&2
    if _docker_exec "${docker_cmd}" build -t "${image_name}" -f "${dockerfile}" "${dockerfile_dir}"; then
        echo "✓ Image built successfully: ${image_name}" >&2
        echo "${image_name}"
        return 0
    else
        echo "✗ Failed to build image from Dockerfile" >&2
        return 1
    fi
}

_resolve_image() {
    local image_arg="$1"
    local docker_cmd="$2" container_name="$3"
    if _is_dockerfile "${image_arg}"; then
        _build_from_dockerfile "${image_arg}" "${docker_cmd}" "${container_name}"
    else
        echo "${image_arg}"
    fi
}

_resolve_container_name() {
    local arg="$1"
    if [[ -z "${arg}" ]]; then
        _get_container_name
    elif [[ "${arg}" =~ ^[0-9]+$ ]]; then
        local name="$(_get_container_by_index "${arg}")"
        [[ -z "${name}" ]] && echo "" || echo "${name}"
    else
        echo "${arg}"
    fi
}

_merge_config() {
    local container_name="$1"
    local ports_override="$2"
    local image_override="$3"
    local cmd_override="$4"
    local project_override="$5"
    
    # Load config once
    local config=$(_load_config "${container_name}")
    
    # Get values with priority: override > config > default
    local ports="${ports_override:-$(_get_config_value "${config}" "ports" "")}"
    local image="${image_override:-$(_get_config_value "${config}" "image" "${FAST_DEV_CONTAINER_IMAGE}")}"
    local docker_cmd="${cmd_override:-$(_get_config_value "${config}" "docker_cmd" "${FAST_DEV_CONTAINER_DOCKER}")}"
    local project_path="${project_override:-$(_get_config_value "${config}" "project_path" "$PWD")}"
    
    # Convert Dockerfile to absolute path
    if [[ -f "${image}" ]]; then
        image="$(_absolute_path "${image}")"
    fi
    
    # Output as space-separated values
    echo "${ports}|${image}|${docker_cmd}|${project_path}"
}

dev_start() {
    local container_arg="" ports_override="" image_override="" cmd_override=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p) ports_override="$2"; shift 2 ;;
            -i) image_override="$2"; shift 2 ;;
            -c) cmd_override="$2"; shift 2 ;;
            *) container_arg="$1"; shift ;;
        esac
    done
    
    local container_name="$(_resolve_container_name "${container_arg}")"
    [[ -z "${container_name}" ]] && { echo "✗ No container found at index ${container_arg}. Run 'dev_list'." >&2; return 1; }
    
    # Merge config with overrides
    IFS='|' read -r ports image_config docker_cmd project_path <<< "$(_merge_config "${container_name}" "${ports_override}" "${image_override}" "${cmd_override}" "")"
    
    # Resolve image (build from Dockerfile if needed)
    local image=$(_resolve_image "${image_config}" "${docker_cmd}" "${container_name}") || { echo "✗ Failed to resolve image" >&2; return 1; }
    
    if _container_exists "${container_name}" "${docker_cmd}"; then
        echo "→ Starting '${container_name}'..."
        [[ -n "${ports}" ]] && echo "  Ports: ${ports}"
        _docker_exec "${docker_cmd}" start "${container_name}" >/dev/null 2>&1 || { echo "✗ Failed to start" >&2; return 1; }
        echo "✓ Attaching..."
        _docker_exec "${docker_cmd}" exec -it -w /workspace "${container_name}" bash
    else
        echo "→ Creating '${container_name}' [${image}]"
        [[ -n "${ports}" ]] && echo "  Ports: ${ports}"
        
        local port_flags_arr=()
        while IFS= read -r line; do port_flags_arr+=("$line"); done < <(_build_port_flags "${ports}")
        
        _docker_exec "${docker_cmd}" run -d --name "${container_name}" -v "${project_path}:/workspace" "${port_flags_arr[@]}" "${image}" || { echo "✗ Failed to create" >&2; return 1; }
        _save_config "${container_name}" "${ports}" "${image_config}" "${docker_cmd}" "${project_path}"
        
        echo "✓ Created, attaching..."
        _docker_exec "${docker_cmd}" exec -it -w /workspace "${container_name}" bash
    fi
}

dev_new() {
    local ports_override="" image_override="" cmd_override=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p) ports_override="$2"; shift 2 ;;
            -i) image_override="$2"; shift 2 ;;
            -c) cmd_override="$2"; shift 2 ;;
            *) echo "✗ Unknown argument: $1" >&2; return 1 ;;
        esac
    done
    
    local container_name="$(basename "$PWD")_$(date +%s)"
    
    # Merge config with overrides
    IFS='|' read -r ports image_config docker_cmd project_path <<< "$(_merge_config "${container_name}" "${ports_override}" "${image_override}" "${cmd_override}" "$PWD")"
    
    # Resolve image
    local image=$(_resolve_image "${image_config}" "${docker_cmd}" "${container_name}") || { echo "✗ Failed to resolve image" >&2; return 1; }
    
    local port_flags_arr=()
    while IFS= read -r line; do port_flags_arr+=("$line"); done < <(_build_port_flags "${ports}")
    
    echo "→ Creating '${container_name}' [${image}]"
    [[ -n "${ports}" ]] && echo "  Ports: ${ports}"
    
    _docker_exec "${docker_cmd}" run -d --name "${container_name}" -v "${project_path}:/workspace" "${port_flags_arr[@]}" "${image}" || { echo "✗ Failed to create" >&2; return 1; }
    _save_config "${container_name}" "${ports}" "${image_config}" "${docker_cmd}" "${project_path}"
    
    echo "✓ Created, attaching..."
    _docker_exec "${docker_cmd}" exec -it -w /workspace "${container_name}" bash
}

dev_stop() {
    local container_arg="" cmd_override=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c) cmd_override="$2"; shift 2 ;;
            *) container_arg="$1"; shift ;;
        esac
    done
    
    local container_name="$(_resolve_container_name "${container_arg}")"
    [[ -z "${container_name}" ]] && { echo "✗ No container found at index ${container_arg}. Run 'dev_list'." >&2; return 1; }
    
    local docker_cmd="${cmd_override:-$(_get_config "${container_name}" "docker_cmd")}"
    docker_cmd="${docker_cmd:-${FAST_DEV_CONTAINER_DOCKER}}"
    
    _container_exists "${container_name}" "${docker_cmd}" || { echo "✗ Container '${container_name}' not found" >&2; return 1; }
    
    echo "→ Stopping '${container_name}'..."
    _docker_exec "${docker_cmd}" stop "${container_name}" >/dev/null 2>&1 && echo "✓ Stopped" || { echo "✗ Failed" >&2; return 1; }
}

dev_rm() {
    local force=false with_config=false container_arg="" cmd_override=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            --with-config) with_config=true; shift ;;
            -c) cmd_override="$2"; shift 2 ;;
            *) container_arg="$1"; shift ;;
        esac
    done
    
    local container_name="$(_resolve_container_name "${container_arg}")"
    [[ -z "${container_name}" ]] && { echo "✗ No container found at index ${container_arg}. Run 'dev_list'." >&2; return 1; }
    
    local docker_cmd="${cmd_override:-$(_get_config "${container_name}" "docker_cmd")}"
    docker_cmd="${docker_cmd:-${FAST_DEV_CONTAINER_DOCKER}}"
    
    _container_exists "${container_name}" "${docker_cmd}" || { echo "✗ Container '${container_name}' not found" >&2; return 1; }
    
    # Remove container
    if [[ "$force" == true ]]; then
        echo "→ Force removing '${container_name}'..."
        _docker_exec "${docker_cmd}" rm -f "${container_name}" >/dev/null 2>&1 || { echo "✗ Failed to remove" >&2; return 1; }
    else
        echo "→ Stopping and removing '${container_name}'..."
        _docker_exec "${docker_cmd}" stop "${container_name}" >/dev/null 2>&1 || { echo "✗ Failed to stop. Use -f to force." >&2; return 1; }
        _docker_exec "${docker_cmd}" rm "${container_name}" >/dev/null 2>&1 || { echo "✗ Failed to remove" >&2; return 1; }
    fi
    
    # Handle config
    if [[ "$with_config" == true ]]; then
        _remove_config "${container_name}"
        echo "✓ Container and config deleted"
    else
        echo "✓ Container deleted (config preserved)"
    fi
}

dev_help() {
    cat "${HELP_FILE}"
}

dev_list() {
    local current_dir_container="$(_get_container_name)"
    _docker_exec "${FAST_DEV_CONTAINER_DOCKER}" ps -a --filter "name=^dev_" --format '{{.Names}}|||{{.Status}}|||{{.Image}}' 2>/dev/null | \
    ${FAST_DEV_CONTAINER_PYTHON} "${UTILS_PY}" list_containers "${CONFIG_FILE}" "${current_dir_container}"
}