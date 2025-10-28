#!/usr/bin/env bash

: "${FDEVC_PYTHON:=python3}"
: "${FDEVC_DOCKER:=docker}"
# shellcheck disable=SC2296
if [[ -n "${ZSH_VERSION}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
: "${FDEVC_IMAGE:=fdevc:latest}"
CONFIG_FILE="${SCRIPT_DIR}/.fdevc_config.json"
UTILS_PY="${SCRIPT_DIR}/utils.py"
HELP_FILE="${SCRIPT_DIR}/help.txt"

_check_dependencies() {
    local missing=()
    local docker_base_cmd
    docker_base_cmd=$(echo "${FDEVC_DOCKER}" | awk '{print $1}')
    if ! command -v "${docker_base_cmd}" &>/dev/null; then missing+=("${docker_base_cmd}"); fi
    if ! command -v "${FDEVC_PYTHON}" &>/dev/null; then missing+=("${FDEVC_PYTHON}"); fi
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

# shellcheck disable=SC2317
if ! _check_dependencies; then return 1 2>/dev/null || exit 1; fi

# Color and styling helpers
_c_reset="\033[0m"
_c_bold="\033[1m"
_c_dim="\033[2m"
_c_blue="\033[94m"
_c_cyan="\033[96m"
_c_green="\033[92m"
_c_yellow="\033[93m"
_c_red="\033[91m"
_c_magenta="\033[95m"

_icon_arrow="→"
_icon_check="✓"
_icon_cross="✗"
_icon_info="ℹ"
_icon_running="●"
_icon_stopped="○"
_icon_saved="◌"

_msg_info() { echo -e "${_c_bold}${_c_cyan}${_icon_arrow}${_c_reset} ${_c_bold}$*${_c_reset}"; }
_msg_success() { echo -e "${_c_bold}${_c_green}${_icon_check}${_c_reset} ${_c_green}$*${_c_reset}"; }
_msg_error() { echo -e "${_c_bold}${_c_red}${_icon_cross}${_c_reset} ${_c_red}$*${_c_reset}" >&2; }
_msg_warning() { echo -e "${_c_bold}${_c_yellow}⚠${_c_reset} ${_c_yellow}$*${_c_reset}"; }
_msg_detail() { echo -e "  ${_c_dim}$*${_c_reset}"; }
_msg_highlight() { echo -e "${_c_bold}${_c_blue}$*${_c_reset}"; }
_msg_docker_cmd() { echo -e "${_c_magenta}$ $*${_c_reset}"; }

_docker_exec() {
    local docker_cmd="$1"
    shift
    local docker_parts
    # Split docker command string into array so overrides like "docker -H host" work (support bash/zsh)
    if [[ -n "${ZSH_VERSION-}" ]]; then
        read -rA docker_parts <<< "${docker_cmd}"
    else
        read -r -a docker_parts <<< "${docker_cmd}"
    fi
    "${docker_parts[@]}" "$@"
}
_get_container_name() { echo "fdevc.$(basename "$PWD")"; }

_generate_project_label() {
    ${FDEVC_PYTHON} "${UTILS_PY}" random_label
}

_prepare_save_config_args() {
    local no_volume="$1" no_socket="$2" project_path="$3" socket_config="$4"
    local project_to_save="${project_path}"
    if [[ "${no_volume}" == true ]]; then
        project_to_save=""
    fi
    local socket_to_save="${socket_config}"
    if [[ "${no_socket}" == true ]]; then
        socket_to_save="false"
    elif [[ -z "${socket_to_save}" ]]; then
        socket_to_save="true"
    fi
    echo "${project_to_save}|${socket_to_save}"
}
_container_exists() {
    _docker_exec "${2:-${FDEVC_DOCKER}}" ps -a --filter "name=^$1$" --format '{{.Names}}' 2>/dev/null | grep -q "^$1$"
}
_container_running() {
    _docker_exec "${2:-${FDEVC_DOCKER}}" ps --filter "name=^$1$" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q "^$1$"
}

_container_image_name() {
    local image_name
    image_name=$(_docker_exec "${2:-${FDEVC_DOCKER}}" inspect --format '{{.Config.Image}}' "$1" 2>/dev/null || true)
    echo "${image_name}"
}

_remove_image_if_exists() {
    local image_ref="$1" docker_cmd="${2:-${FDEVC_DOCKER}}"
    [[ -z "${image_ref}" ]] && return 0
    
    # Try to remove the image (by name or ID)
    # Docker will only remove the tag if multiple tags point to the same image
    # If it's the last reference, it will remove the actual image
    _docker_exec "${docker_cmd}" image rm "${image_ref}" >/dev/null 2>&1 || true
}
_get_container_by_index() {
    local id="$1"
    local docker_output
    docker_output=$(_docker_exec "${FDEVC_DOCKER}" ps -a --filter "name=^fdevc\\." --format '{{.Names}}|||{{.Status}}|||{{.Image}}' 2>/dev/null)
    printf '%s\n' "${docker_output}" | ${FDEVC_PYTHON} "${UTILS_PY}" resolve_index "${CONFIG_FILE}" "${id}"
}

_load_config() {
    local container_name="$1"
    [[ ! -f "${CONFIG_FILE}" ]] && echo "{}" && return
    ${FDEVC_PYTHON} "${UTILS_PY}" load_config "${CONFIG_FILE}" "${container_name}" 2>/dev/null
}

_get_config_value() {
    local config="$1" key="$2" default="$3"
    local value
    value=$(echo "${config}" | ${FDEVC_PYTHON} "${UTILS_PY}" get_config_value "${key}" "${default}" 2>/dev/null)
    echo "${value:-${default}}"
}

_get_config() {
    local container_name="$1"
    local key="$2"
    local config
    config=$(_load_config "${container_name}")
    _get_config_value "${config}" "${key}"
}

_container_created_at() {
    local container_name="$1" docker_cmd="${2:-${FDEVC_DOCKER}}"
    _docker_exec "${docker_cmd}" inspect --format '{{.Created}}' "${container_name}" 2>/dev/null || true
}

_handle_port_conflict() {
    local error_output="$1" docker_cmd="${2:-${FDEVC_DOCKER}}"
    
    # Check if it's a port conflict
    if echo "${error_output}" | grep -qE "(Bind for 0.0.0.0|port is already allocated|address already in use)"; then
        local conflicting_port=""
        
        # Try multiple patterns to extract the port
        conflicting_port=$(echo "${error_output}" | grep -oP 'Bind for 0.0.0.0:\K[0-9]+' | head -1)
        if [[ -z "${conflicting_port}" ]]; then
            conflicting_port=$(echo "${error_output}" | grep -oP '0.0.0.0:\K[0-9]+' | head -1)
        fi
        if [[ -z "${conflicting_port}" ]]; then
            conflicting_port=$(echo "${error_output}" | grep -oP ':\K[0-9]+(?=: bind:)' | head -1)
        fi
        if [[ -z "${conflicting_port}" ]]; then
            conflicting_port=$(echo "${error_output}" | grep -oP 'port \K[0-9]+' | head -1)
        fi
        
        if [[ -n "${conflicting_port}" ]]; then
            _msg_detail "Port ${conflicting_port} is already in use"
            # Find which container is using this port
            local blocking_container
            blocking_container=$(_docker_exec "${docker_cmd}" ps -a --format '{{.Names}}|||{{.Ports}}' 2>/dev/null | grep ":${conflicting_port}->" | cut -d'|' -f1 | head -1)
            if [[ -n "${blocking_container}" ]]; then
                echo -e "  ${_c_bold}${_c_yellow}⚠ Blocked by container: ${_c_blue}${blocking_container}${_c_reset}"
                echo -e "  ${_c_dim}Run: ${_c_reset}${_c_bold}fdevc stop ${blocking_container}${_c_reset}"
            fi
        else
            # If we can't extract the port, just show generic message
            _msg_detail "Port conflict detected"
        fi
    fi
}

_copy_local_script_to_container() {
    local container_name="$1"
    local docker_cmd="$2"
    local startup_cmd="$3"
    
    if [[ -z "${startup_cmd}" ]]; then
        echo "${startup_cmd}"
        return 0
    fi
    
    local script_path="${startup_cmd%% *}"  # Extract first word (script path)
    if [[ -f "${script_path}" || ( "${script_path}" == ./* && -f "${script_path#./}" ) ]]; then
        local source_file="${script_path}"
        [[ "${source_file}" == ./* ]] && source_file="${source_file#./}"
        if [[ -f "${source_file}" ]]; then
            { _msg_info "Copying local script to container..."; } >&2
            { _msg_detail "Source: ${source_file}"; } >&2
            _docker_exec "${docker_cmd}" exec "${container_name}" mkdir -p /workspace >/dev/null 2>&1
            local basename_script
            basename_script="$(basename "${source_file}")"
            if _docker_exec "${docker_cmd}" cp "${source_file}" "${container_name}:/workspace/${basename_script}" >/dev/null 2>&1 \
                && _docker_exec "${docker_cmd}" exec "${container_name}" chmod +x "/workspace/${basename_script}" >/dev/null 2>&1; then
                { _msg_success "Script copied to /workspace/${basename_script}"; } >&2
                # Update startup command to use the copied script
                echo "${startup_cmd/${script_path}/./${basename_script}}"
                return 0
            else
                { _msg_error "Failed to copy script to container"; } >&2
            fi
        fi
    fi
    
    echo "${startup_cmd}"
}

_build_attach_command() {
    local startup_cmd="$1"
    local persist="${2:-false}"
    local run_on_reattach="${3:-false}"  # true if -c was used (run every time)
    
    if [[ "${persist}" == "true" ]]; then
        # For persistent containers, use tmux for session persistence
        local session_name="fdevc_persistent"
        local cmd="if command -v tmux >/dev/null 2>&1; then "
        cmd+="  if tmux has-session -t ${session_name} 2>/dev/null; then "
        cmd+="    echo -e '\\033[1m\\033[94m→ Reattaching to persistent session...\\033[0m'; "
        # Run -c command even on reattach if specified
        if [[ -n "${startup_cmd}" && "${run_on_reattach}" == "true" ]]; then
            cmd+="    tmux send-keys -t ${session_name} 'cd /workspace; ${startup_cmd}' C-m; "
        fi
        cmd+="    exec tmux attach-session -t ${session_name}; "
        cmd+="  else "
        cmd+="    echo -e '\\033[1m\\033[94m→ Creating persistent session...\\033[0m'; "
        cmd+="    cd /workspace; "
        if [[ -n "${startup_cmd}" ]]; then
            cmd+="    ${startup_cmd}; "
        fi
        # Create session with a shell that has exit function to detach
        cmd+="    exec tmux new-session -s ${session_name} \"bash --rcfile <(echo 'source ~/.bashrc 2>/dev/null || true; exit() { tmux detach-client; }') -i\"; "
        cmd+="  fi; "
        cmd+="else "
        cmd+="  echo -e '\\033[1m\\033[93m⚠ Warning: tmux not found, session will not persist\\033[0m'; "
        cmd+="  cd /workspace; "
        if [[ -n "${startup_cmd}" ]]; then
            cmd+="  ${startup_cmd}; "
        fi
        cmd+="  exec bash -l; "
        cmd+="fi"
    else
        # For non-persistent containers, reattach to tmux if exists but override exit to actually exit
        local session_name="fdevc_persistent"
        local cmd="if command -v tmux >/dev/null 2>&1 && tmux has-session -t ${session_name} 2>/dev/null; then "
        cmd+="  echo -e '\\033[1m\\033[94m→ Reattaching to session (stop on exit)...\\033[0m'; "
        # Override exit function to kill tmux session and then exit the shell
        cmd+="  tmux send-keys -t ${session_name} 'exit() { tmux kill-session -t ${session_name}; builtin exit; }' C-m; "
        cmd+="  exec tmux attach-session -t ${session_name}; "
        cmd+="else "
        cmd+="  cd /workspace"
        if [[ -n "${startup_cmd}" ]]; then
            cmd+="; ${startup_cmd}"
        fi
        cmd+="; exec bash -l; "
        cmd+="fi"
    fi
    
    echo "${cmd}"
}

_attach_session() {
    local container_name="$1"
    local docker_cmd="$2"
    local startup_cmd="$3"
    local persist="$4"
    local run_on_reattach="$5"
    local detach="$6"
    local has_tty="$7"
    shift 7
    local attach_msg_stop="$1"; shift
    local attach_msg_persist="$1"; shift
    local noninteractive_run_msg="$1"; shift
    local noninteractive_skip_msg="$1"; shift
    local noninteractive_run_level="${1:-warning}"

    if [[ "${has_tty}" == true ]]; then
        local attach_message="${attach_msg_stop}"
        if [[ "${detach}" == true ]]; then
            attach_message="${attach_msg_persist}"
        fi
        _msg_success "${attach_message}"
        local attach_cmd
        attach_cmd=$(_build_attach_command "${startup_cmd}" "${persist}" "${run_on_reattach}")
        local docker_exec_args=(exec -i -t -w /workspace "${container_name}" bash -lc "${attach_cmd}")
        _docker_exec "${docker_cmd}" "${docker_exec_args[@]}"
        return $?
    fi

    if [[ -n "${startup_cmd}" ]]; then
        if [[ "${noninteractive_run_level}" == "success" ]]; then
            _msg_success "${noninteractive_run_msg}"
        else
            _msg_warning "${noninteractive_run_msg}"
        fi
        local noninteractive_cmd="cd /workspace; ${startup_cmd}"
        _docker_exec "${docker_cmd}" exec -i -w /workspace "${container_name}" bash -lc "${noninteractive_cmd}"
        return $?
    fi

    _msg_warning "${noninteractive_skip_msg}"
    return 0
}

_save_config() {
    local container_name="$1"
    local ports="$2"
    local image="$3"
    local docker_cmd="$4"
    local project_path="$5"
    local startup_cmd="$6"
    local socket_state="$7"
    local created_at="$8"
    local persist="$9"

    mkdir -p "$(dirname "${CONFIG_FILE}")"
    # Ensure we pass a proper string representation of the boolean
    local persist_str="false"
    [[ "${persist}" == "true" || "${persist}" == "1" ]] && persist_str="true"
    
    ${FDEVC_PYTHON} "${UTILS_PY}" save_config "${CONFIG_FILE}" "${container_name}" "${ports}" "${image}" "${docker_cmd}" "${project_path}" "${startup_cmd}" "${socket_state}" "${created_at}" "${persist_str}" 2>/dev/null
}

_remove_config() {
    local container_name="$1"
    [[ ! -f "${CONFIG_FILE}" ]] && return 0
    ${FDEVC_PYTHON} "${UTILS_PY}" remove_config "${CONFIG_FILE}" "${container_name}" 2>/dev/null
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
    local dockerfile="$1" docker_cmd="${2:-${FDEVC_DOCKER}}" container_name="${3:-fdevc.custom}"
    if [[ ! -f "${dockerfile}" ]]; then
        _msg_error "Dockerfile not found: ${dockerfile}"
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
    local dockerfile_dir
    dockerfile_dir="$(dirname "${dockerfile}")"
    if _docker_exec "${docker_cmd}" images -q "${image_name}" 2>/dev/null | grep -q .; then
        _msg_info "Using cached image: ${image_name}" >&2
        echo "${image_name}"
        return 0
    fi
    _msg_info "Building image from Dockerfile: ${dockerfile}" >&2
    _msg_detail "Image tag: ${image_name}" >&2
    _msg_detail "Building..." >&2
    if _docker_exec "${docker_cmd}" build -t "${image_name}" -f "${dockerfile}" "${dockerfile_dir}"; then
        _msg_success "Image built: ${image_name}" >&2
        echo "${image_name}"
        return 0
    else
        _msg_error "Failed to build image from Dockerfile"
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
        local name
        name="$(_get_container_by_index "${arg}")"
        [[ -z "${name}" ]] && echo "" || echo "${name}"
    else
        echo "${arg}"
    fi
}

_merge_config() {
    local container_name="$1"
    local ports_override="$2"
    local image_override="$3"
    local docker_cmd_override="$4"
    local project_override="$5"
    local socket_override="$6"
    
    # Load config once
    local config
    config=$(_load_config "${container_name}")
    local config_present="false"
    if [[ -n "${config}" && "${config}" != "{}" ]]; then
        config_present="true"
    fi
    
    # Determine default image: prioritize fdevc.Dockerfile in current directory
    local default_image="${FDEVC_IMAGE}"
    if [[ -f "$PWD/fdevc.Dockerfile" ]]; then
        default_image="$PWD/fdevc.Dockerfile"
    fi
    
    # Get values with priority: override > config > default
    local ports="${ports_override:-$(_get_config_value "${config}" "ports" "")}" 
    local image="${image_override:-$(_get_config_value "${config}" "image" "${default_image}")}" 
    local docker_cmd="${docker_cmd_override:-$(_get_config_value "${config}" "docker_cmd" "${FDEVC_DOCKER}")}" 

    local project_from_config
    project_from_config="$(_get_config_value "${config}" "project_path" "__DEVCONF_NO_PROJECT__")"
    local project_path=""
    if [[ -n "${project_override}" && "${project_override}" != "__NO_PROJECT__" ]]; then
        project_path="${project_override}"
    elif [[ "${project_override}" == "__NO_PROJECT__" ]]; then
        # Explicitly no project (e.g., VM mode)
        project_path=""
    elif [[ "${project_from_config}" == "__DEVCONF_NO_PROJECT__" ]]; then
        project_path="$PWD"
    else
        project_path="${project_from_config}"
    fi

    local socket_from_config
    socket_from_config="$(_get_config_value "${config}" "socket" "__DEVCONF_NO_SOCKET__")"
    local socket_value=""
    if [[ -n "${socket_override}" ]]; then
        socket_value="${socket_override}"
    elif [[ "${socket_from_config}" == "__DEVCONF_NO_SOCKET__" ]]; then
        socket_value=""
    else
        socket_value="${socket_from_config}"
    fi

    local startup_cmd
    startup_cmd="$(_get_config_value "${config}" "startup_cmd" "")"
    local persist_mode_raw
    persist_mode_raw="$(_get_config_value "${config}" "persist" "false")"
    local persist_mode_value="false"
    local persist_mode_lower
    persist_mode_lower=$(printf '%s' "${persist_mode_raw}" | tr '[:upper:]' '[:lower:]')
    case "${persist_mode_lower}" in
        true|"1"|yes) persist_mode_value="true" ;;
    esac
    
    # Convert Dockerfile to absolute path
    if [[ -f "${image}" ]]; then
        image="$(_absolute_path "${image}")"
    fi
    
    # Output as space-separated values
    echo "${ports}|${image}|${docker_cmd}|${project_path}|${startup_cmd}|${socket_value}|${config_present}|${persist_mode_value}"
}

_fdevc_start() {
    local container_arg="" ports_override="" image_override="" docker_cmd_override="" detach=false remove_on_exit=false
    local no_volume=false no_socket=false force_new=false force_recreate=false vm_mode=false
    local startup_cmd_once="" startup_cmd_save="" startup_cmd_save_flag=false ignore_startup_cmd=false
    local detach_user_set=false
    local copy_config_from="" custom_basename=""
    local has_tty=true
    if [[ ! -t 0 || ! -t 1 ]]; then
        has_tty=false
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p) ports_override="$2"; shift 2 ;;
            -i) image_override="$2"; shift 2 ;;
            --dkr) docker_cmd_override="$2"; shift 2 ;;
            --tmp) remove_on_exit=true; shift ;;
            -d) detach=true; detach_user_set=true; shift ;;
            --no-d) detach=false; detach_user_set=true; shift ;;
            --no-v) no_volume=true; shift ;;
            --no-s) no_socket=true; shift ;;
            -c) startup_cmd_once="$2"; shift 2 ;;
            --c-s) startup_cmd_once="$2"; startup_cmd_save="$2"; startup_cmd_save_flag=true; shift 2 ;;
            --no-c) ignore_startup_cmd=true; shift ;;
            -f|--force) force_recreate=true; shift ;;
            --new) force_new=true; shift ;;
            --vm) vm_mode=true; no_volume=true; no_socket=true; shift ;;
            --cp) copy_config_from="$2"; shift 2 ;;
            -n) custom_basename="$2"; shift 2 ;;
            --) shift; break ;;
            *) 
                if [[ "$1" == -* ]]; then
                    _msg_error "Unknown option: $1"
                    return 1
                fi
                if [[ "${force_new}" == true ]] || [[ "${vm_mode}" == true ]]; then
                    _msg_error "Unknown argument: $1"
                    return 1
                fi
                container_arg="$1"
                shift
                ;;
        esac
    done

    if [[ "${remove_on_exit}" == true && "${detach}" == true ]]; then
        _msg_info "--tmp overrides -d; container stops and is removed."
        detach=false
    fi

    if [[ "${ignore_startup_cmd}" == true ]]; then
        startup_cmd_once=""
        startup_cmd_save=""
        startup_cmd_save_flag=false
    fi

    # Resolve --cp (copy config from) if provided
    local copy_config_source=""
    if [[ -n "${copy_config_from}" ]]; then
        copy_config_source="$(_resolve_container_name "${copy_config_from}")"
        if [[ -z "${copy_config_source}" ]]; then
            _msg_error "Config source not found: ${copy_config_from}. Run 'fdevc ls'."
            return 1
        fi
        # Verify config exists
        local source_config
        source_config=$(_load_config "${copy_config_source}")
        if [[ -z "${source_config}" || "${source_config}" == "{}" ]]; then
            _msg_error "No config found for: ${copy_config_source}"
            return 1
        fi
        _msg_info "Copying config from: ${copy_config_source}"
    fi

    local overrides_supplied=false
    [[ -n "${ports_override}" || -n "${image_override}" || -n "${docker_cmd_override}" ]] && overrides_supplied=true
    local container_running=false
    local container_was_running=false
    local image_to_remove_after_create=""

    # Determine container name based on mode
    local container_name
    local config_target_name
    local is_vm_copy=false
    
    # Check if copying from a VM container to preserve VM mode
    if [[ -n "${copy_config_from}" ]]; then
        local source_name
        source_name="$(_resolve_container_name "${copy_config_from}")"
        if [[ "${source_name}" == fdevc.vm.* ]]; then
            is_vm_copy=true
        fi
    fi
    
    if [[ -n "${custom_basename}" ]]; then
        # Custom basename provided with -n
        # Determine the final container name first
        local proposed_name
        if [[ "${vm_mode}" == true ]] || [[ "${is_vm_copy}" == true ]]; then
            proposed_name="fdevc.vm.${custom_basename}"
        else
            proposed_name="fdevc.${custom_basename}"
        fi
        
        # Check for name collision (exact match or with .tmp suffix)
        if [[ "${force_recreate}" != true ]]; then
            local collision_check
            collision_check=$(_docker_exec "${FDEVC_DOCKER}" ps -a --filter "name=^${proposed_name}$" --filter "name=^${proposed_name}.tmp$" --format '{{.Names}}' 2>/dev/null | head -1)
            if [[ -z "${collision_check}" && -f "${CONFIG_FILE}" ]]; then
                # Also check saved configs
                collision_check=$(${FDEVC_PYTHON} -c "import json; data = json.load(open('${CONFIG_FILE}')); print('${proposed_name}' if '${proposed_name}' in data or '${proposed_name}.tmp' in data else '')" 2>/dev/null)
            fi
            if [[ -n "${collision_check}" ]]; then
                _msg_error "Name collision: container '${collision_check}' already exists"
                _msg_detail "Choose a different basename with -n, use --force to replace, or remove the existing container"
                return 1
            fi
        else
            # Force mode: remove any existing container with this name
            local existing_container
            existing_container=$(_docker_exec "${FDEVC_DOCKER}" ps -a --filter "name=^${proposed_name}$" --filter "name=^${proposed_name}.tmp$" --format '{{.Names}}' 2>/dev/null | head -1)
            if [[ -n "${existing_container}" ]]; then
                _msg_info "Force mode: removing existing container '${existing_container}'..."
                _docker_exec "${FDEVC_DOCKER}" rm -f "${existing_container}" >/dev/null 2>&1
                _remove_config "${existing_container}"
            fi
        fi
        
        container_name="${proposed_name}"
        config_target_name="${container_name}"
    elif [[ "${vm_mode}" == true ]]; then
        # VM mode: generate special name fdevc.vm.<random-name>
        container_name="fdevc.vm.$(_generate_project_label)"
        config_target_name="${container_name}"
    elif [[ "${force_new}" == true ]]; then
        container_name="fdevc.$(basename "$PWD").$(date +%s)"
        config_target_name="${container_name}"
    elif [[ "${no_volume}" == true && -z "${container_arg}" ]]; then
        # --no-v mode without specific container: generate random name
        container_name="fdevc.$(_generate_project_label)"
        config_target_name="${container_name}"
    else
        container_name="$(_resolve_container_name "${container_arg}")"
        [[ -z "${container_name}" ]] && { _msg_error "No container found at id ${container_arg}. Run 'fdevc ls'."; return 1; }
        config_target_name="${container_name}"
    fi

    # Prefer base configuration when available (unless tmp requested or --cp used)
    if [[ "${force_new}" != true && "${remove_on_exit}" != true && -z "${copy_config_source}" ]]; then
        local base_config_name="${config_target_name}"
        base_config_name="${base_config_name%.tmp}"
        if [[ "${base_config_name}" != "${config_target_name}" ]]; then
            local base_config_json
            base_config_json="$(_load_config "${base_config_name}")"
            if [[ -n "${base_config_json}" && "${base_config_json}" != "{}" ]]; then
                config_target_name="${base_config_name}"
                container_name="${base_config_name}"
            fi
        fi
    fi

    local base_container_name="${container_name}"
    base_container_name="${base_container_name%.tmp}"

    local socket_override_arg=""
    [[ "${no_socket}" == true ]] && socket_override_arg="false"

    # Merge config with overrides (use copy source if --cp provided)
    local merge_project_path=""
    if [[ "${vm_mode}" == true ]] || [[ "${is_vm_copy}" == true ]]; then
        # VM mode or copying from VM: explicitly set no project path (sentinel value)
        merge_project_path="__NO_PROJECT__"
        # For VM copy, ensure socket is disabled unless explicitly set
        if [[ "${is_vm_copy}" == true && "${no_socket}" != true && -z "${socket_override_arg}" ]]; then
            no_socket=true
            socket_override_arg="false"
        fi
    elif [[ "${force_new}" == true ]]; then
        # New mode: use current directory
        merge_project_path="$PWD"
    elif [[ -n "${copy_config_source}" ]]; then
        # When copying config, check if source has no project_path (e.g., VM container)
        # If so, preserve that state instead of defaulting to PWD
        local source_project
        source_project=$(_get_config "${copy_config_source}" "project_path")
        if [[ -z "${source_project}" ]]; then
            merge_project_path="__NO_PROJECT__"
        fi
    fi
    local config_source="${copy_config_source:-${config_target_name}}"
    IFS='|' read -r ports image_config docker_cmd project_path startup_cmd_config socket_config config_present persist_mode_config <<< "$(_merge_config "${config_source}" "${ports_override}" "${image_override}" "${docker_cmd_override}" "${merge_project_path}" "${socket_override_arg}")"
    local startup_cmd_session="${startup_cmd_once:-${startup_cmd_config}}"
    local run_on_reattach=false
    [[ -n "${startup_cmd_once}" ]] && run_on_reattach=true
    local startup_cmd_to_save="${startup_cmd_config}"
    if [[ "${startup_cmd_save_flag}" == true ]]; then
        startup_cmd_to_save="${startup_cmd_save}"
    fi

    if [[ "${ignore_startup_cmd}" == true ]]; then
        startup_cmd_session=""
    fi

    # If user explicitly set detach mode, mirror it into persist setting
    if [[ "${detach_user_set}" == true ]]; then
        if [[ "${detach}" == "true" && "${remove_on_exit}" != "true" ]]; then
            persist_mode_config="true"
        else
            persist_mode_config="false"
        fi
    fi
    
    # Use persist_mode_config as the source of truth
    local persist_from_config="${persist_mode_config}"

    # Auto-enable detach if persist is true and not explicitly set by user
    if [[ "${persist_from_config}" == "true" && "${detach_user_set}" == false && "${remove_on_exit}" != true ]]; then
        detach=true
    fi

    if [[ "${remove_on_exit}" == true ]]; then
        container_name="${base_container_name}.tmp"
    else
        container_name="${base_container_name}"
    fi

    # Check if container exists (skip for force_new)
    local container_exists=false
    if [[ "${force_new}" != true ]] && _container_exists "${container_name}" "${docker_cmd}"; then
        container_exists=true
    fi

    if [[ "${container_exists}" == true ]]; then
        if _container_running "${container_name}" "${docker_cmd}"; then
            container_running=true
            container_was_running=true
        fi
    fi

    local desired_effective_project_path="${project_path}"
    if [[ "${no_volume}" == true ]]; then
        desired_effective_project_path=""
    fi
    local desired_project_to_save="" desired_socket_to_save=""
    IFS='|' read -r desired_project_to_save desired_socket_to_save <<< "$(_prepare_save_config_args "${no_volume}" "${no_socket}" "${desired_effective_project_path}" "${socket_config}")"

    local config_differs=false
    if [[ "${force_recreate}" == true ]]; then
        local saved_config
        saved_config="$(_load_config "${container_name}")"
        if [[ -n "${saved_config}" && "${saved_config}" != "{}" ]]; then
            local saved_ports saved_image saved_docker_cmd saved_project_path saved_socket_state
            saved_ports=$(_get_config_value "${saved_config}" "ports" "")
            saved_image=$(_get_config_value "${saved_config}" "image" "")
            saved_docker_cmd=$(_get_config_value "${saved_config}" "docker_cmd" "")
            saved_project_path=$(_get_config_value "${saved_config}" "project_path" "")
            saved_socket_state=$(_get_config_value "${saved_config}" "socket" "")
            if [[ "${saved_ports}" != "${ports}" || "${saved_image}" != "${image_config}" || "${saved_docker_cmd}" != "${docker_cmd}" || "${saved_project_path}" != "${desired_project_to_save}" || "${saved_socket_state}" != "${desired_socket_to_save}" ]]; then
                config_differs=true
            fi
        else
            if [[ "${overrides_supplied}" == true || "${no_socket}" == true || "${no_volume}" == true ]]; then
                config_differs=true
            fi
        fi
    fi

    if [[ "${container_exists}" == true ]]; then
        local should_recreate=false
        if [[ "${force_recreate}" == true && "${config_differs}" == true ]]; then
            should_recreate=true
        elif [[ "${overrides_supplied}" == true ]]; then
            if [[ "${container_running}" == true ]]; then
                _msg_info "Running '${container_name}'; overrides ignored. Use --new/-f or stop first."
                overrides_supplied=false
            else
                should_recreate=true
            fi
        fi

        if [[ "${should_recreate}" == true ]]; then
            image_to_remove_after_create="$(_container_image_name "${container_name}" "${docker_cmd}")"
            if [[ "${container_running}" == true ]]; then
                _msg_info "Recreating '${container_name}' (remove running container)..."
            else
                _msg_info "Recreating '${container_name}' with new settings..."
            fi
            if ! _docker_exec "${docker_cmd}" rm -f "${container_name}" >/dev/null 2>&1; then
                _msg_error "Failed to recreate container with new settings"
                return 1
            fi
            container_exists=false
            container_running=false
            container_was_running=false
        fi
    fi

    local exec_status=0
    # Determine persist mode: user override takes precedence over config
    local persist_to_save="${persist_from_config}"
    
    # Temporary containers are never persistent
    if [[ "${remove_on_exit}" == true ]]; then
        persist_to_save="false"
    elif [[ "${detach_user_set}" == true ]]; then
        if [[ "${detach}" == "true" ]]; then
            persist_to_save="true"
        else
            persist_to_save="false"
        fi
    fi

    if [[ "${container_exists}" == true ]]; then
        if [[ "${remove_on_exit}" != true ]]; then
            local created_at_current_save
            created_at_current_save="$(_container_created_at "${container_name}" "${docker_cmd}")"
            _save_config "${container_name}" "${ports}" "${image_config}" "${docker_cmd}" "${desired_project_to_save}" "${startup_cmd_to_save}" "${desired_socket_to_save}" "${created_at_current_save}" "${persist_to_save}"
        fi

        if [[ "${container_running}" == true ]]; then
            _msg_info "Already running: '${container_name}'"
        else
            _msg_info "Starting '${container_name}'..."
            [[ -n "${ports}" ]] && _msg_detail "Ports: ${ports}"
            _msg_docker_cmd "${docker_cmd} start ${container_name}"
            local start_error exit_code
            start_error=$(_docker_exec "${docker_cmd}" start "${container_name}" 2>&1)
            exit_code=$?
            if [[ ${exit_code} -ne 0 ]]; then
                _msg_error "Failed to start"
                _handle_port_conflict "${start_error}" "${docker_cmd}"
                return 1
            fi
            container_running=true
        fi
        if [[ "${remove_on_exit}" == true && "${container_was_running}" == true ]]; then
            _msg_info "--tmp ignored (container already running)."
            remove_on_exit=false
        fi

        # Copy local script if --no-v is used and startup command references a local file
        if [[ "${no_volume}" == true && -n "${startup_cmd_session}" ]]; then
            startup_cmd_session=$(_copy_local_script_to_container "${container_name}" "${docker_cmd}" "${startup_cmd_session}")
        fi

        _attach_session "${container_name}" "${docker_cmd}" "${startup_cmd_session}" \
            "${persist_to_save}" "${run_on_reattach}" "${detach}" "${has_tty}" \
            "Attaching (stop on exit)..." \
            "Attaching (persist on exit)..." \
            "No TTY detected; running startup command without interactive shell." \
            "No TTY detected and no startup command configured; skipping interactive attach." \
            warning
        exec_status=$?
    else
        if [[ "${remove_on_exit}" != true ]]; then
            _save_config "${container_name}" "${ports}" "${image_config}" "${docker_cmd}" "${desired_project_to_save}" "${startup_cmd_to_save}" "${desired_socket_to_save}" "" "${persist_to_save}"
        fi

        local image
        image=$(_resolve_image "${image_config}" "${docker_cmd}" "${container_name}") || { _msg_error "Failed to resolve image"; return 1; }

        _msg_info "Creating '${container_name}' (image: ${image})"
        [[ -n "${ports}" ]] && _msg_detail "Ports: ${ports}"

        local port_flags_arr=()
        while IFS= read -r line; do port_flags_arr+=("$line"); done < <(_build_port_flags "${ports}")

        local run_args=(-d --name "${container_name}")
        local socket_label="false"
        if [[ "${no_volume}" != true && -n "${project_path}" ]]; then
            run_args+=(-v "${project_path}:/workspace")
        fi
        if [[ "${no_socket}" != true ]]; then
            run_args+=(-v /var/run/docker.sock:/var/run/docker.sock)
            socket_label="true"
        fi
        run_args+=(--label "fdevc.socket=${socket_label}")
        run_args+=("${port_flags_arr[@]}" "${image}")

        _msg_docker_cmd "${docker_cmd} run ${run_args[*]}"
        local error_output exit_code
        error_output=$(_docker_exec "${docker_cmd}" run "${run_args[@]}" 2>&1)
        exit_code=$?
        if [[ ${exit_code} -ne 0 ]]; then
            _msg_error "Failed to create"
            _handle_port_conflict "${error_output}" "${docker_cmd}"
            return 1
        fi
        if [[ "${remove_on_exit}" != true ]]; then
            local created_at_current_post
            created_at_current_post="$(_container_created_at "${container_name}" "${docker_cmd}")"
            if [[ -n "${created_at_current_post}" ]]; then
                _save_config "${container_name}" "${ports}" "${image_config}" "${docker_cmd}" "${desired_project_to_save}" "${startup_cmd_to_save}" "${desired_socket_to_save}" "${created_at_current_post}" "${persist_to_save}"
            fi
        fi

        # Copy local script if --no-v is used and startup command references a local file
        if [[ "${no_volume}" == true && -n "${startup_cmd_session}" ]]; then
            startup_cmd_session=$(_copy_local_script_to_container "${container_name}" "${docker_cmd}" "${startup_cmd_session}")
        fi

        _attach_session "${container_name}" "${docker_cmd}" "${startup_cmd_session}" \
            "${persist_to_save}" "${run_on_reattach}" "${detach}" "${has_tty}" \
            "Created, attaching (stop on exit)..." \
            "Created; attaching (persist on exit)..." \
            "Created; running startup command without interactive shell..." \
            "Created container but no TTY detected; skip attach (no startup command)." \
            success
        exec_status=$?

        if [[ -n "${image_to_remove_after_create}" ]]; then
            _remove_image_if_exists "${image_to_remove_after_create}" "${docker_cmd}"
        fi
    fi

    # Only skip stopping if persist mode is enabled
    # If user explicitly set non-persistent (--no-d), we should stop even if container was running
    if [[ "${persist_to_save}" == "true" ]]; then
        return "${exec_status}"
    fi

    _msg_info "Stopping '${container_name}'..."
    _msg_docker_cmd "${docker_cmd} stop ${container_name}"
    if _docker_exec "${docker_cmd}" stop "${container_name}" >/dev/null 2>&1; then
        _msg_success "Stopped"
        if [[ "${remove_on_exit}" == true ]]; then
            _msg_info "Removing '${container_name}'..."
            _msg_docker_cmd "${docker_cmd} rm -f ${container_name}"
            local image_to_remove_on_exit
            image_to_remove_on_exit="$(_container_image_name "${container_name}" "${docker_cmd}")"
            if _docker_exec "${docker_cmd}" rm -f "${container_name}" >/dev/null 2>&1; then
                _msg_success "Removed"
                _remove_image_if_exists "${image_to_remove_on_exit}" "${docker_cmd}"
            else
                _msg_error "Failed to remove '${container_name}'"
            fi
        fi
    else
        _msg_error "Failed to stop '${container_name}'"
    fi

    return "${exec_status}"
}

_fdevc_new() {
    # Wrapper that creates a new timestamped container
    _fdevc_start --new "$@"
}

_fdevc_vm() {
    # Wrapper for VM mode: no volume, no socket, random name
    _fdevc_start --vm "$@"
}

_fdevc_stop() {
    local container_arg="" docker_cmd_override=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dkr) docker_cmd_override="$2"; shift 2 ;;
            *) container_arg="$1"; shift ;;
        esac
    done

    local container_name
    container_name="$(_resolve_container_name "${container_arg}")"
    [[ -z "${container_name}" ]] && { _msg_error "No container found at id ${container_arg}. Run 'fdevc ls'."; return 1; }

    local docker_cmd="${docker_cmd_override:-$(_get_config "${container_name}" "docker_cmd")}"
    docker_cmd="${docker_cmd:-${FDEVC_DOCKER}}"

    _msg_info "Stopping '${container_name}'..."
    _container_exists "${container_name}" "${docker_cmd}" || { _msg_error "Container '${container_name}' not found"; return 1; }
    _msg_docker_cmd "${docker_cmd} stop ${container_name}"
    if _docker_exec "${docker_cmd}" stop "${container_name}" >/dev/null 2>&1; then
        _msg_success "Stopped"
    else
        _msg_error "Failed"
        return 1
    fi
}

_fdevc_rm() {
    local force=false with_config=false container_arg="" docker_cmd_override=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            --all) with_config=true; shift ;;
            --dkr) docker_cmd_override="$2"; shift 2 ;;
            *) container_arg="$1"; shift ;;
        esac
    done
    
    local container_name
    container_name="$(_resolve_container_name "${container_arg}")"
    [[ -z "${container_name}" ]] && { _msg_error "No container found at id ${container_arg}. Run 'fdevc ls'."; return 1; }

    local docker_cmd="${docker_cmd_override:-$(_get_config "${container_name}" "docker_cmd")}"
    docker_cmd="${docker_cmd:-${FDEVC_DOCKER}}"

    local config_json
    config_json=$(_load_config "${container_name}")
    config_json="${config_json//$'\n'/}"
    local has_config=false
    [[ -n "${config_json}" && "${config_json}" != "{}" ]] && has_config=true

    local container_exists=false
    if _container_exists "${container_name}" "${docker_cmd}"; then
        container_exists=true
    fi

    if [[ "${container_exists}" == false ]]; then
        if [[ "${has_config}" == true ]]; then
            _msg_info "Removing saved config '${container_name}'..."
            _remove_config "${container_name}"
            _msg_success "Config deleted"
            return 0
        else
            _msg_error "Container '${container_name}' not found"
            return 1
        fi
    fi

    # Get image name before removing container
    local image_to_remove=""
    if [[ "${with_config}" == true ]]; then
        image_to_remove="$(_container_image_name "${container_name}" "${docker_cmd}")"
    fi
    
    # Remove container
    if [[ "${force}" == true ]]; then
        _msg_info "Force removing '${container_name}'..."
        _msg_docker_cmd "${docker_cmd} rm -f ${container_name}"
        _docker_exec "${docker_cmd}" rm -f "${container_name}" >/dev/null 2>&1 || { _msg_error "Failed to remove"; return 1; }
    else
        _msg_info "Stopping and removing '${container_name}'..."
        _msg_docker_cmd "${docker_cmd} stop ${container_name}"
        _docker_exec "${docker_cmd}" stop "${container_name}" >/dev/null 2>&1 || { _msg_error "Failed to stop. Use -f to force"; return 1; }
        _msg_docker_cmd "${docker_cmd} rm ${container_name}"
        _docker_exec "${docker_cmd}" rm "${container_name}" >/dev/null 2>&1 || { _msg_error "Failed to remove container"; return 1; }
    fi
    
    # Handle config and image
    if [[ "${with_config}" == true ]]; then
        _remove_config "${container_name}"
        if [[ -n "${image_to_remove}" ]]; then
            _remove_image_if_exists "${image_to_remove}" "${docker_cmd}"
        fi
        _msg_success "Container, config, and image deleted"
    else
        _msg_success "Container deleted (config preserved)"
    fi
}

_fdevc_custom() {
    local target_file="fdevc.Dockerfile"

    if [[ -f "${target_file}" ]]; then
        _msg_error "fdevc.Dockerfile already exists in current directory"
        return 1
    fi

    if [[ ! -f "${FDEVC_IMAGE}" ]]; then
        _msg_error "Template Dockerfile not found at: ${FDEVC_IMAGE}"
        return 1
    fi
    
    _msg_info "Copying template Dockerfile to ${target_file}..."
    cp "${FDEVC_IMAGE}" "${target_file}" || { _msg_error "Failed to copy template"; return 1; }
    _msg_success "Created ${target_file}"
    _msg_detail "This file will be used by default for containers in this directory"
}

_fdevc_gen() {
    local project_name=""
    
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        _msg_error "Usage: fdevc gen <name>"
        _msg_detail "Creates a fdevc runnable project"
        return 1
    fi
    
    project_name="$1"
    
    # Validate project name
    if [[ "${project_name}" =~ [[:space:]] ]]; then
        _msg_error "Project name cannot contain spaces"
        return 1
    fi
    
    # Check if project already exists
    if [[ -e "${project_name}" ]]; then
        _msg_error "'${project_name}' already exists"
        return 1
    fi
    
    # Check if templates directory exists
    local templates_dir="${SCRIPT_DIR}/templates"
    if [[ ! -d "${templates_dir}" ]]; then
        _msg_error "Templates directory not found at: ${templates_dir}"
        return 1
    fi
    
    # Verify all required templates exist
    local required_templates=("runnable.sh" "launch.sh" "install_and_run" "README.md")
    for template in "${required_templates[@]}"; do
        if [[ ! -f "${templates_dir}/${template}" ]]; then
            _msg_error "Missing template: ${template}"
            return 1
        fi
    done
    
    _msg_info "Creating fdevc runnable project: ${project_name}"
    
    # Create project folder
    mkdir -p "${project_name}" || { _msg_error "Failed to create project"; return 1; }
    cd "${project_name}" || { _msg_error "Failed to enter project"; return 1; }
    
    _msg_success "Created project: ${project_name}"
    
    # Copy and process templates
    _msg_info "Creating runnable.sh..."
    cp "${templates_dir}/runnable.sh" "./runnable.sh" || { _msg_error "Failed to create runnable.sh"; return 1; }
    chmod +x "./runnable.sh"
    _msg_success "Created runnable.sh"
    
    _msg_info "Creating launch.sh..."
    sed "s/__PROJECT__/${project_name}/g" "${templates_dir}/launch.sh" > "./launch.sh" || { _msg_error "Failed to create launch.sh"; return 1; }
    chmod +x "./launch.sh"
    _msg_success "Created launch.sh"
    
    _msg_info "Creating install_and_run script..."
    sed "s/__PROJECT__/${project_name}/g" "${templates_dir}/install_and_run" > "./install_and_run" || { _msg_error "Failed to create install_and_run"; return 1; }
    chmod +x "./install_and_run"
    _msg_success "Created install_and_run"
    
    _msg_info "Creating README.md..."
    sed -e "s/__PROJECT__/${project_name}/g" \
        "${templates_dir}/README.md" > "./README.md" || { _msg_error "Failed to create README.md"; return 1; }
    _msg_success "Created README.md"
    
    echo ""
    _msg_success "Runnable project created successfully!"
    echo -e "${_c_bold}${_c_cyan}📁 Current Location: ${_c_reset}${PWD}"
    echo ""
    echo -e "${_c_bold}${_c_cyan}Next steps:${_c_reset}"
    echo -e "  ${_c_bold}1.${_c_reset} ${_c_yellow}Replace ${_c_bold}__USER__${_c_reset}${_c_yellow} with your GitHub username${_c_reset} (see README.md)"
    echo -e "  ${_c_bold}2.${_c_reset} Edit ${_c_bold}runnable.sh${_c_reset} to add your setup commands"
    echo -e "  ${_c_bold}3.${_c_reset} Edit ${_c_bold}launch.sh${_c_reset} to configure container settings"
    echo -e "  ${_c_bold}4.${_c_reset} Optional: Run ${_c_bold}fdevc custom${_c_reset} to create a custom Dockerfile"
    echo -e "  ${_c_bold}5.${_c_reset} Test locally: ${_c_bold}./launch.sh${_c_reset}"
    echo -e "  ${_c_bold}6.${_c_reset} Push to GitHub and share: ${_c_dim}curl -fsSL https://raw.githubusercontent.com/<user>/${project_name}/main/install_and_run | bash${_c_reset}"
}

_fdevc_help() {
    cat "${HELP_FILE}"
}

_fdevc_ls() {
    _docker_exec "${FDEVC_DOCKER}" ps -a --filter "name=^fdevc\\." --format '{{.Names}}|||{{.Status}}|||{{.Image}}|||{{.Mounts}}|||{{.Label "fdevc.socket"}}|||{{.CreatedAt}}' 2>/dev/null | \
    ${FDEVC_PYTHON} "${UTILS_PY}" list_containers "${CONFIG_FILE}"
}

_fdevc_config() {
    local remove_all=false
    local remove_target=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --rm)
                if [[ -n "$2" && "$2" != -* ]]; then
                    remove_target="$2"
                    shift 2
                else
                    remove_all=true
                    shift
                fi
                ;;
            *)
                _msg_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    if [[ "${remove_all}" == true ]]; then
        ${FDEVC_PYTHON} "${UTILS_PY}" remove_all_configs "${CONFIG_FILE}"
    elif [[ -n "${remove_target}" ]]; then
        # Check if it's an id
        if [[ "${remove_target}" =~ ^[0-9]+$ ]]; then
            local container_name
            container_name=$(_get_container_by_index "${remove_target}")
            if [[ -z "${container_name}" ]]; then
                _msg_error "No configuration found at id ${remove_target}"
                return 1
            fi
            remove_target="${container_name}"
        fi
        _remove_config "${remove_target}"
        _msg_success "Configuration '${remove_target}' removed"
    else
        ${FDEVC_PYTHON} "${UTILS_PY}" list_configs "${CONFIG_FILE}"
    fi
}

# Main dispatcher function
fdevc() {
    if [[ $# -eq 0 ]]; then
        # No arguments - default to start
        _fdevc_start
        return $?
    fi

    local subcommand="$1"
    
    case "${subcommand}" in
        -h|--help)
            _fdevc_help
            ;;
        start)
            shift
            _fdevc_start "$@"
            ;;
        new)
            shift
            _fdevc_new "$@"
            ;;
        stop)
            shift
            _fdevc_stop "$@"
            ;;
        rm)
            shift
            _fdevc_rm "$@"
            ;;
        custom)
            shift
            _fdevc_custom "$@"
            ;;
        gen)
            shift
            _fdevc_gen "$@"
            ;;
        config)
            shift
            _fdevc_config "$@"
            ;;
        vm)
            shift
            _fdevc_vm "$@"
            ;;
        ls)
            shift
            _fdevc_ls "$@"
            ;;
        *)
            # If it looks like a flag or number, pass it to start
            if [[ "${subcommand}" =~ ^- ]] || [[ "${subcommand}" =~ ^[0-9]+$ ]]; then
                _fdevc_start "$@"
            else
                # Otherwise it might be a container name - pass to start
                _fdevc_start "$@"
            fi
            ;;
    esac
}