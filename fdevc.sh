#!/usr/bin/env bash

: "${FDEVC_PYTHON:=python3}"
: "${FDEVC_DOCKER:=docker}"
# shellcheck disable=SC2296
if [[ -n "${ZSH_VERSION}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
: "${FDEVC_IMAGE:=philogicae/fdevc:latest}"
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

_msg_info() { echo -e "${_c_bold}${_c_cyan}${_icon_arrow}${_c_reset} ${_c_cyan}$*${_c_reset}"; }
_msg_success() { echo -e "${_c_bold}${_c_green}${_icon_check}${_c_reset} ${_c_green}$*${_c_reset}"; }
_msg_error() { echo -e "${_c_bold}${_c_red}${_icon_cross}${_c_reset} ${_c_red}$*${_c_reset}" >&2; }
_msg_warning() { echo -e "${_c_bold}${_c_yellow}⚠${_c_reset} ${_c_yellow}$*${_c_reset}"; }
_msg_detail() { echo -e "  ${_c_dim}$*${_c_reset}"; }
_msg_highlight() { echo -e "${_c_bold}${_c_blue}$*${_c_reset}"; }
_msg_docker_cmd() { echo -e "${_c_magenta}$ $*${_c_reset}"; }

_format_container_title() {
    local name="$1"
    echo -e "${_c_bold}${_c_blue}${name}${_c_reset}"
}

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
_get_container_name() {
    local basename_pwd
    basename_pwd=$(basename "$PWD")
    echo "fdevc.${basename_pwd:-root}"
}

_generate_project_label() {
    ${FDEVC_PYTHON} "${UTILS_PY}" random_label
}

_prepare_save_config_args() {
    local no_socket="$1" socket_config="$2"
    local socket_to_save="${socket_config}"
    if [[ "${no_socket}" == true ]]; then
        socket_to_save="false"
    elif [[ -z "${socket_to_save}" ]]; then
        socket_to_save="true"
    fi
    echo "${socket_to_save}"
}
_container_exists() {
    _docker_exec "${2:-${FDEVC_DOCKER}}" ps -a --filter "name=^$1$" --format '{{.Names}}' 2>/dev/null | grep -q "^$1$"
}

_container_running() {
    _docker_exec "${2:-${FDEVC_DOCKER}}" ps --filter "name=^$1$" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q "^$1$"
}

_container_status() {
    local container_name="$1" docker_cmd="${2:-${FDEVC_DOCKER}}"
    if _container_running "${container_name}" "${docker_cmd}"; then
        echo "running"
    elif _container_exists "${container_name}" "${docker_cmd}"; then
        echo "stopped"
    else
        echo "missing"
    fi
}

_container_image_name() {
    _docker_exec "${2:-${FDEVC_DOCKER}}" inspect --format '{{.Config.Image}}' "$1" 2>/dev/null || true
}

_remove_image_if_exists() {
    local image_ref="$1" docker_cmd="${2:-${FDEVC_DOCKER}}"
    [[ -z "${image_ref}" ]] && return 0
    [[ "${image_ref}" == "${FDEVC_IMAGE}" ]] && return 0
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
    local container_name="$1" key="$2" default="$3"
    local config
    config=$(_load_config "${container_name}")
    _get_config_value "${config}" "${key}" "${default}"
}

_container_created_at() {
    local container_name="$1" docker_cmd="${2:-${FDEVC_DOCKER}}"
    _docker_exec "${docker_cmd}" inspect --format '{{.Created}}' "${container_name}" 2>/dev/null || true
}

_extract_port_from_error() {
    local error_output="$1"
    local patterns=("Bind for 0.0.0.0:\K[0-9]+" "0.0.0.0:\K[0-9]+" ":\K[0-9]+(?=: bind:)" "port \K[0-9]+")
    
    for pattern in "${patterns[@]}"; do
        local port
        port=$(echo "${error_output}" | grep -oP "${pattern}" | head -1)
        if [[ -n "${port}" ]]; then
            echo "${port}"
            return 0
        fi
    done
    return 1
}

_handle_port_conflict() {
    local error_output="$1" docker_cmd="${2:-${FDEVC_DOCKER}}"
    
    # Check if it's a port conflict
    if ! echo "${error_output}" | grep -qE "(Bind for 0.0.0.0|port is already allocated|address already in use)"; then
        return 0
    fi
    
    local conflicting_port
    if conflicting_port=$(_extract_port_from_error "${error_output}"); then
        _msg_detail "Port ${conflicting_port} is already in use"
        # Find which container is using this port
        local blocking_container
        blocking_container=$(_docker_exec "${docker_cmd}" ps -a --format '{{.Names}}|||{{.Ports}}' 2>/dev/null | grep ":${conflicting_port}->" | cut -d'|' -f1 | head -1)
        if [[ -n "${blocking_container}" ]]; then
            echo -e "  ${_c_bold}${_c_yellow}⚠ Blocked by container: ${_c_blue}${blocking_container}${_c_reset}"
            echo -e "  ${_c_dim}Run: ${_c_reset}${_c_bold}fdevc stop ${blocking_container}${_c_reset}"
        fi
    else
        _msg_detail "Port conflict detected"
    fi
}

_is_workspace_mounted() {
    local volumes_str="$1"
    local project_path="$2"
    [[ -z "${volumes_str}" ]] && return 1
    
    local volume_list=()
    if [[ -n "${ZSH_VERSION-}" ]]; then
        IFS='|||' read -rA volume_list <<< "${volumes_str}"
    else
        IFS='|||' read -r -a volume_list <<< "${volumes_str}"
    fi
    
    for vol in "${volume_list[@]}"; do
        [[ -z "${vol}" ]] && continue
        local expanded_vol
        expanded_vol=$(_expand_volume "${vol}" "${project_path}")
        [[ "${expanded_vol}" == *:/workspace* ]] && return 0
    done
    return 1
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
            { _msg_info "Copying local script to container"; } >&2
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
        cmd+="    echo -e '\\033[1m\\033[94m→ Reattaching to persistent session\\033[0m'; "
        # Run -c command even on reattach if specified
        if [[ -n "${startup_cmd}" && "${run_on_reattach}" == "true" ]]; then
            cmd+="    tmux send-keys -t ${session_name} 'cd /workspace; ${startup_cmd}' C-m; "
        fi
        cmd+="    exec tmux attach-session -t ${session_name}; "
        cmd+="  else "
        cmd+="    echo -e '\\033[1m\\033[94m→ Creating persistent session\\033[0m'; "
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
        cmd+="  echo -e '\\033[1m\\033[94m→ Reattaching to session (stop on exit)\\033[0m'; "
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
    local volumes="${10}"
    mkdir -p "$(dirname "${CONFIG_FILE}")"
    local persist_str="false"
    [[ "${persist}" == "true" || "${persist}" == "1" ]] && persist_str="true"
    local collapsed_project=""
    [[ -n "${project_path}" ]] && collapsed_project=$(_collapse_path "${project_path}" "")
    local collapsed_startup="${startup_cmd}"
    if [[ -n "${startup_cmd}" ]]; then
        local first_word="${startup_cmd%% *}"
        if [[ -f "${first_word}" || "${first_word}" == __*__* || "${first_word}" == ~* || "${first_word}" == /* ]]; then
            collapsed_startup=$(_collapse_path "${startup_cmd}" "${project_path}")
        fi
    fi
    local collapsed_volumes=""
    if [[ -n "${volumes}" ]]; then
        local volume_list=()
        if [[ -n "${ZSH_VERSION-}" ]]; then
            IFS='|||' read -rA volume_list <<< "${volumes}"
        else
            IFS='|||' read -r -a volume_list <<< "${volumes}"
        fi
        local collapsed_vol_list=()
        for vol in "${volume_list[@]}"; do
            [[ -z "${vol}" || "${vol}" == "/var/run/docker.sock:/var/run/docker.sock" ]] && continue
            # shellcheck disable=SC2155
            local normalized_vol=$(_normalize_volume_name "${vol}" "${container_name}" "${project_path}")
            # shellcheck disable=SC2155
            local collapsed_vol=$(_collapse_volume "${normalized_vol}" "${project_path}")
            collapsed_vol_list+=("${collapsed_vol}")
        done
        
        # Sort volumes: mount volumes (with :) first, then excluded volumes (without :)
        local mount_volumes=()
        local excluded_volumes=()
        for vol in "${collapsed_vol_list[@]}"; do
            if [[ "${vol}" == *:* ]]; then
                mount_volumes+=("${vol}")
            else
                excluded_volumes+=("${vol}")
            fi
        done
        local sorted_volumes=("${mount_volumes[@]}" "${excluded_volumes[@]}")
        
        if [[ ${#sorted_volumes[@]} -gt 0 ]]; then
            local first=true
            for vol in "${sorted_volumes[@]}"; do
                if [[ "${first}" == true ]]; then
                    collapsed_volumes="${vol}"
                    first=false
                else
                    collapsed_volumes="${collapsed_volumes}|||${vol}"
                fi
            done
        fi
    fi
    ${FDEVC_PYTHON} "${UTILS_PY}" save_config "${CONFIG_FILE}" "${container_name}" "${ports}" "${image}" "${docker_cmd}" "${collapsed_project}" "${collapsed_startup}" "${socket_state}" "${created_at}" "${persist_str}" "${collapsed_volumes}" 2>/dev/null
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

_is_dockerfile() { [[ -f "$1" ]]; }
_absolute_path() {
    local path="$1"
    [[ "${path}" == /* ]] && { printf '%s\n' "${path}"; return; }
    
    local dir="${path%/*}"
    [[ "${dir}" == "${path}" ]] && dir=.
    
    if cd "${dir}" 2>/dev/null; then
        printf '%s/%s\n' "$(pwd)" "${path##*/}"
    else
        printf '%s\n' "${path}"
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
    _msg_detail "Building" >&2
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
    case "${arg}" in
        "") _get_container_name ;;
        [0-9]*) _get_container_by_index "${arg}" ;;
        *) echo "${arg}" ;;
    esac
}

_get_default_image() {
    [[ -f "$PWD/fdevc.Dockerfile" ]] && echo "$PWD/fdevc.Dockerfile" || echo "${FDEVC_IMAGE}"
}

_resolve_project_path() {
    local project_override="$1" project_from_config="$2"
    case "${project_override}" in
        "__NO_PROJECT__") echo "" ;;
        "") echo "${project_from_config}" ;;
        *) echo "${project_override}" ;;
    esac
}

_resolve_socket_value() {
    local socket_override="$1" socket_from_config="$2"
    
    if [[ -n "${socket_override}" ]]; then
        echo "${socket_override}"
    elif [[ "${socket_from_config}" == "__DEVCONF_NO_SOCKET__" ]]; then
        echo ""
    else
        echo "${socket_from_config}"
    fi
}

_normalize_persist_value() {
    local persist_raw="$1"
    local persist_lower
    persist_lower=$(printf '%s' "${persist_raw}" | tr '[:upper:]' '[:lower:]')
    case "${persist_lower}" in
        true|"1"|yes) echo "true" ;;
        *) echo "false" ;;
    esac
}

_collapse_path() {
    local path="$1" project_path="${2:-}"
    [[ -z "${path}" ]] && return 0
    local home_expanded="${HOME}"
    if [[ -n "${project_path}" && "${path}" == "${project_path}"* ]]; then
        echo "${path/${project_path}/__PROJECT_PATH__}"
    elif [[ "${path}" == "${home_expanded}"* ]]; then
        echo "${path/${home_expanded}/__HOME__}"
    else
        echo "${path}"
    fi
}

_expand_path() {
    local path="$1" project_path="${2:-}"
    [[ -z "${path}" ]] && return 0
    if [[ "${path}" == __PROJECT_PATH__* ]]; then
        if [[ -z "${project_path}" ]]; then
            echo "${path}"
        else
            echo "${path/__PROJECT_PATH__/${project_path}}"
        fi
    elif [[ "${path}" == __HOME__* ]]; then
        echo "${path/__HOME__/${HOME}}"
    else
        echo "${path}"
    fi
}

_collapse_volume() {
    local volume="$1" project_path="${2:-}"
    local vol_source="${volume%%:*}"
    local vol_target="${volume#*:}"
    if [[ "${vol_source}" == ./* ]]; then
        if [[ -z "${project_path}" || "${project_path}" == "__NO_PROJECT__" ]]; then
            local abs_path
            abs_path=$(cd "$(dirname "${vol_source}")" 2>/dev/null && pwd)/$(basename "${vol_source}")
            vol_source=$(_collapse_path "${abs_path}" "")
        else
            vol_source="__PROJECT_PATH__${vol_source#.}"
        fi
    else
        vol_source=$(_collapse_path "${vol_source}" "${project_path}")
    fi
    if [[ "${volume}" == *:* ]]; then
        if [[ "${vol_target}" == ./* ]]; then
            vol_target="/workspace${vol_target#.}"
        fi
        echo "${vol_source}:${vol_target}"
    else
        echo "${vol_source}"
    fi
}

_expand_volume() {
    local volume="$1" project_path="${2:-}"
    [[ -z "${volume}" ]] && return 0
    local vol_source="${volume%%:*}"
    local vol_target="${volume#*:}"
    local expanded_source
    expanded_source=$(_expand_path "${vol_source}" "${project_path}")
    if [[ "${expanded_source}" == ./* ]]; then
        if [[ -n "${project_path}" && "${project_path}" != "__NO_PROJECT__" ]]; then
            expanded_source="${project_path}${expanded_source#.}"
        else
            expanded_source="${PWD}${expanded_source#.}"
        fi
    fi
    if [[ "${volume}" == *:* ]]; then
        if [[ "${vol_target}" == ./* ]]; then
            vol_target="/workspace${vol_target#.}"
        fi
        echo "${expanded_source}:${vol_target}"
    else
        echo "${expanded_source}"
    fi
}

_normalize_volume_name() {
    local volume="$1" container_name="$2" project_path="${3:-}"
    [[ -z "${volume}" ]] && return 0
    
    local expanded_vol
    expanded_vol=$(_expand_volume "${volume}" "${project_path}")
    
    local vol_source="${expanded_vol%%:*}"
    local vol_target="${expanded_vol#*:}"
    if [[ "${vol_source}" != /* && "${vol_source}" != ./* && "${expanded_vol}" == *:* ]]; then
        # Check if already has container prefix (from config)
        if [[ "${vol_source}" != "${container_name}."* ]]; then
            vol_source="${container_name}.${vol_source}"
        fi
    fi
    
    if [[ "${expanded_vol}" == *:* ]]; then
        echo "${vol_source}:${vol_target}"
    else
        echo "${vol_source}"
    fi
}

_merge_config() {
    local container_name="$1" ports_override="$2" image_override="$3" docker_cmd_override="$4" project_override="$5" socket_override="$6" volumes_override="$7"
    local config
    config=$(_load_config "${container_name}")
    local config_present="false"
    [[ -n "${config}" && "${config}" != "{}" ]] && config_present="true"
    local default_image
    default_image=$(_get_default_image)
    local ports="${ports_override:-$(_get_config_value "${config}" "ports" "")}" 
    local image="${image_override:-$(_get_config_value "${config}" "image" "${default_image}")}" 
    local docker_cmd="${docker_cmd_override:-$(_get_config_value "${config}" "docker_cmd" "${FDEVC_DOCKER}")}" 
    local project_from_config
    project_from_config="$(_get_config_value "${config}" "project_path" "")"
    local project_path
    if [[ -n "${project_override}" ]]; then
        project_path="${project_override}"
    elif [[ -n "${project_from_config}" ]]; then
        project_path="${project_from_config}"
    elif [[ "${config_present}" == "false" ]]; then
        project_path="$PWD"
    else
        project_path=""
    fi
    local socket_from_config
    socket_from_config="$(_get_config_value "${config}" "socket" "__DEVCONF_NO_SOCKET__")"
    local socket_value
    socket_value=$(_resolve_socket_value "${socket_override}" "${socket_from_config}")
    local volumes_from_config
    volumes_from_config="$(_get_config_value "${config}" "volumes" "")"
    local volumes="${volumes_override:-${volumes_from_config}}"
    local startup_cmd
    startup_cmd="$(_get_config_value "${config}" "startup_cmd" "")"
    local persist_mode_raw
    persist_mode_raw="$(_get_config_value "${config}" "persist" "false")"
    local persist_mode_value
    persist_mode_value=$(_normalize_persist_value "${persist_mode_raw}")
    [[ -f "${image}" ]] && image="$(_absolute_path "${image}")"
    echo "${ports}|${image}|${docker_cmd}|${project_path}|${startup_cmd}|${socket_value}|${config_present}|${persist_mode_value}|${volumes}"
}

_validate_container_name() {
    local container_name="$1" context="${2:-operation}"
    if [[ -z "${container_name}" ]]; then
        _msg_error "No container found for ${context}. Run 'fdevc ls'."
        return 1
    fi
}

_stop_container() {
    local container_name="$1" docker_cmd="$2"
    _msg_info "Stopping $(_format_container_title "${container_name}")"
    _msg_docker_cmd "${docker_cmd} stop ${container_name}"
    if _docker_exec "${docker_cmd}" stop "${container_name}" >/dev/null 2>&1; then
        _msg_success "Stopped"
        return 0
    else
        _msg_error "Failed to stop $(_format_container_title "${container_name}")"
        return 1
    fi
}

_remove_container() {
    local container_name="$1" docker_cmd="$2" force="${3:-false}"
    local action="Removing"
    local flags=(-v)
    [[ "${force}" == "true" ]] && { action="Force removing"; flags=(-f -v); }
    
    _msg_info "${action} $(_format_container_title "${container_name}")"
    _msg_docker_cmd "${docker_cmd} rm ${flags[*]} ${container_name}"
    if _docker_exec "${docker_cmd}" rm "${flags[@]}" "${container_name}" >/dev/null 2>&1; then
        _msg_success "Removed"
        return 0
    else
        _msg_error "Failed to remove $(_format_container_title "${container_name}")"
        return 1
    fi
}

_fdevc_start() {
    local container_arg="" ports_override="" image_override="" docker_cmd_override="" detach=false remove_on_exit=false
    local no_dir=false no_socket=false force_new=false force_recreate=false vm_mode=false no_v_dir=false
    local startup_cmd_once="" startup_cmd_save="" startup_cmd_save_flag=false ignore_startup_cmd=false
    local detach_user_set=false
    local copy_config_from="" custom_basename=""
    local volumes_override=()
    local has_tty=true
    [[ ! -t 0 || ! -t 1 ]] && has_tty=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p) ports_override="$2"; shift 2 ;;
            -v) volumes_override+=("$2"); shift 2 ;;
            -i) image_override="$2"; shift 2 ;;
            --dkr) docker_cmd_override="$2"; shift 2 ;;
            --tmp) remove_on_exit=true; shift ;;
            -d) detach=true; detach_user_set=true; shift ;;
            --no-d) detach=false; detach_user_set=true; shift ;;
            --no-dir) no_dir=true; shift ;;
            --no-v-dir) no_v_dir=true; shift ;;
            --no-s) no_socket=true; shift ;;
            -c) startup_cmd_once="$2"; shift 2 ;;
            --c-s) startup_cmd_once="$2"; startup_cmd_save="$2"; startup_cmd_save_flag=true; shift 2 ;;
            --no-c) ignore_startup_cmd=true; shift ;;
            -f|--force) force_recreate=true; shift ;;
            --new) force_new=true; shift ;;
            --vm) vm_mode=true; no_dir=true; no_socket=true; shift ;;
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
                _msg_info "Force mode: removing existing container '${existing_container}'"
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
    elif [[ "${no_dir}" == true && -z "${container_arg}" ]]; then
        container_name="fdevc.$(_generate_project_label)"
        config_target_name="${container_name}"
    else
        container_name="$(_resolve_container_name "${container_arg}")"
        _validate_container_name "${container_name}" "id ${container_arg}" || return 1
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

    local merge_project_path=""
    if [[ "${no_dir}" == true ]]; then
        merge_project_path="__NO_PROJECT__"
    elif [[ "${vm_mode}" == true ]] || [[ "${is_vm_copy}" == true ]]; then
        merge_project_path="__NO_PROJECT__"
        if [[ "${is_vm_copy}" == true && "${no_socket}" != true && -z "${socket_override_arg}" ]]; then
            no_socket=true
            socket_override_arg="false"
        fi
    elif [[ "${force_new}" == true ]]; then
        merge_project_path="$PWD"
    elif [[ -n "${copy_config_source}" ]]; then
        local source_project
        source_project=$(_get_config "${copy_config_source}" "project_path")
        if [[ -z "${source_project}" ]]; then
            merge_project_path="__NO_PROJECT__"
        fi
    fi
    local config_source="${copy_config_source:-${config_target_name}}"
    local volumes_override_str=""
    if [[ ${#volumes_override[@]} -gt 0 ]]; then
        local first=true
        for vol in "${volumes_override[@]}"; do
            if [[ "${first}" == true ]]; then
                volumes_override_str="${vol}"
                first=false
            else
                volumes_override_str="${volumes_override_str}|||${vol}"
            fi
        done
    fi
    IFS='|' read -r ports image_config docker_cmd project_path startup_cmd_config socket_config config_present persist_mode_config volumes_config <<< "$(_merge_config "${config_source}" "${ports_override}" "${image_override}" "${docker_cmd_override}" "${merge_project_path}" "${socket_override_arg}" "${volumes_override_str}")"
    local startup_cmd_expanded="${startup_cmd_config}"
    if [[ -n "${startup_cmd_expanded}" ]]; then
        startup_cmd_expanded=$(_expand_path "${startup_cmd_expanded}" "${project_path}")
    fi
    local startup_cmd_session="${startup_cmd_once:-${startup_cmd_expanded}}"
    local run_on_reattach=false
    [[ -n "${startup_cmd_once}" ]] && run_on_reattach=true
    local startup_cmd_to_save="${startup_cmd_config}"
    if [[ "${startup_cmd_save_flag}" == true ]]; then
        if [[ -f "${startup_cmd_save%% *}" ]]; then
            startup_cmd_to_save=$(_collapse_path "${startup_cmd_save}" "${project_path}")
        else
            startup_cmd_to_save="${startup_cmd_save}"
        fi
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

    local desired_socket_to_save
    desired_socket_to_save=$(_prepare_save_config_args "${no_socket}" "${socket_config}")
    local desired_project_to_save="${project_path}"
    if [[ "${no_dir}" == true ]]; then
        desired_project_to_save=""
    fi
    local volumes_to_save="${volumes_config}"
    if [[ ${#volumes_override[@]} -gt 0 ]]; then
        volumes_to_save="${volumes_override_str}"
    fi
    if [[ "${no_v_dir}" != true && -n "${desired_project_to_save}" ]]; then
        local has_project_vol=false
        if [[ -n "${volumes_to_save}" ]]; then
            echo "${volumes_to_save}" | grep -q "__PROJECT_PATH__" && has_project_vol=true
        fi
        if [[ "${has_project_vol}" == false ]]; then
            [[ -n "${volumes_to_save}" ]] && volumes_to_save="${volumes_to_save}|||"
            volumes_to_save="${volumes_to_save}__PROJECT_PATH__:/workspace"
        fi
    fi
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
            if [[ "${overrides_supplied}" == true || "${no_socket}" == true || "${no_dir}" == true ]]; then
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
                _msg_info "Running $(_format_container_title "${container_name}"); overrides ignored. Use --new/-f or stop first."
                overrides_supplied=false
            else
                should_recreate=true
            fi
        fi

        if [[ "${should_recreate}" == true ]]; then
            image_to_remove_after_create="$(_container_image_name "${container_name}" "${docker_cmd}")"
            if [[ "${container_running}" == true ]]; then
                _msg_info "Recreating $(_format_container_title "${container_name}") (remove running container)"
            else
                _msg_info "Recreating $(_format_container_title "${container_name}") with new settings"
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
            _save_config "${container_name}" "${ports}" "${image_config}" "${docker_cmd}" "${desired_project_to_save}" "${startup_cmd_to_save}" "${desired_socket_to_save}" "${created_at_current_save}" "${persist_to_save}" "${volumes_to_save}"
        fi

        if [[ "${container_running}" == true ]]; then
            _msg_info "Already running: $(_format_container_title "${container_name}")"
        else
            _msg_info "Starting $(_format_container_title "${container_name}")"
            [[ -n "${ports}" ]] && _msg_detail "Ports: ${ports}"
            _msg_docker_cmd "${docker_cmd} start ${container_name}"
            local start_error exit_code
            start_error=$(_docker_exec "${docker_cmd}" start "${container_name}" 2>&1)
            exit_code=$?
            if [[ ${exit_code} -ne 0 ]]; then
                _msg_error "Failed to start"
                _handle_port_conflict "${start_error}" "${docker_cmd}"
                if [[ -n "${start_error}" ]]; then
                    while IFS= read -r line; do
                        [[ -n "${line}" ]] && _msg_detail "${line}"
                    done <<< "${start_error}"
                fi
                return 1
            fi
            container_running=true
        fi
        if [[ "${remove_on_exit}" == true && "${container_was_running}" == true ]]; then
            _msg_info "--tmp ignored (container already running)."
            remove_on_exit=false
        fi

        if [[ "${no_dir}" == true && -n "${startup_cmd_session}" ]]; then
            # Only copy script if /workspace is not already mounted
            if ! _is_workspace_mounted "${volumes_to_save}" "${project_path}"; then
                startup_cmd_session=$(_copy_local_script_to_container "${container_name}" "${docker_cmd}" "${startup_cmd_session}")
            fi
        fi

        _attach_session "${container_name}" "${docker_cmd}" "${startup_cmd_session}" \
            "${persist_to_save}" "${run_on_reattach}" "${detach}" "${has_tty}" \
            "Attaching (stop on exit)" \
            "Attaching (persist on exit)" \
            "No TTY detected; running startup command without interactive shell" \
            "No TTY detected and no startup command configured; skipping interactive attach" \
            warning
        exec_status=$?
    else
        if [[ "${remove_on_exit}" != true ]]; then
            _save_config "${container_name}" "${ports}" "${image_config}" "${docker_cmd}" "${desired_project_to_save}" "${startup_cmd_to_save}" "${desired_socket_to_save}" "" "${persist_to_save}" "${volumes_to_save}"
        fi

        local image
        image=$(_resolve_image "${image_config}" "${docker_cmd}" "${container_name}") || { _msg_error "Failed to resolve image"; return 1; }

        _msg_info "Creating $(_format_container_title "${container_name}") (image: ${image})"
        [[ -n "${ports}" ]] && _msg_detail "Ports: ${ports}"

        local port_flags_arr=()
        while IFS= read -r line; do port_flags_arr+=("$line"); done < <(_build_port_flags "${ports}")

        local run_args=(-d --name "${container_name}")
        local socket_label="false"
        local dirs_to_create=()
        if [[ -n "${volumes_to_save}" ]]; then
            local volume_list=()
            if [[ -n "${ZSH_VERSION-}" ]]; then
                IFS='|||' read -rA volume_list <<< "${volumes_to_save}"
            else
                IFS='|||' read -r -a volume_list <<< "${volumes_to_save}"
            fi
            for vol in "${volume_list[@]}"; do
                [[ -z "${vol}" ]] && continue
                # shellcheck disable=SC2155
                local normalized_vol=$(_normalize_volume_name "${vol}" "${container_name}" "${project_path}")
                run_args+=(-v "${normalized_vol}")
                local vol_source="${normalized_vol%%:*}"
                # Only create directories for mount volumes (with destination), not excluded volumes
                if [[ "${vol_source}" != /* && "${vol_source}" != ./* && "${normalized_vol}" == *:* && "${normalized_vol}" != *: ]]; then
                    # Extract the container path
                    local container_path="${normalized_vol#*:}"
                    dirs_to_create+=("${container_path}")
                fi
            done
        fi
        if [[ "${no_socket}" != true ]]; then
            run_args+=(-v /var/run/docker.sock:/var/run/docker.sock)
            socket_label="true"
        fi
        run_args+=(--label "fdevc.socket=${socket_label}")
        run_args+=("${port_flags_arr[@]}" "${image}")

        _msg_docker_cmd "${docker_cmd} run ${run_args[*]}"
        if [[ ! -f "${image}" ]] && ! _docker_exec "${docker_cmd}" images -q "${image}" 2>/dev/null | grep -q .; then
            _msg_detail "Pulling image layers"
        fi
        local error_output="" run_output_file=""
        run_output_file=$(mktemp -t fdevc-run-XXXX 2>/dev/null || printf '/tmp/fdevc-run-%s' "$$")
        local exit_code
        if [[ -n "${ZSH_VERSION-}" ]]; then
            (
                setopt pipefail
                _docker_exec "${docker_cmd}" run "${run_args[@]}" 2>&1 | tee "${run_output_file}"
            )
            exit_code=$?
        else
            (
                set -o pipefail
                _docker_exec "${docker_cmd}" run "${run_args[@]}" 2>&1 | tee "${run_output_file}"
            )
            exit_code=$?
        fi
        error_output=$(cat "${run_output_file}" 2>/dev/null || true)
        rm -f "${run_output_file}" 2>/dev/null || true
        if [[ ${exit_code} -ne 0 ]]; then
            _msg_error "Failed to create"
            _handle_port_conflict "${error_output}" "${docker_cmd}"
            if [[ -z "${error_output}" ]]; then
                _msg_detail "Docker did not return additional details."
            fi
            return 1
        fi
        
        # Create directories for virtual volumes
        if [[ ${#dirs_to_create[@]} -gt 0 ]]; then
            for dir_path in "${dirs_to_create[@]}"; do
                _docker_exec "${docker_cmd}" exec "${container_name}" mkdir -p "${dir_path}" >/dev/null 2>&1 || true
            done
        fi
        
        if [[ "${remove_on_exit}" != true ]]; then
            local created_at_current_post
            created_at_current_post="$(_container_created_at "${container_name}" "${docker_cmd}")"
            if [[ -n "${created_at_current_post}" ]]; then
                _save_config "${container_name}" "${ports}" "${image_config}" "${docker_cmd}" "${desired_project_to_save}" "${startup_cmd_to_save}" "${desired_socket_to_save}" "${created_at_current_post}" "${persist_to_save}" "${volumes_to_save}"
            fi
        fi

        if [[ "${no_dir}" == true && -n "${startup_cmd_session}" ]]; then
            # Only copy script if /workspace is not already mounted
            if ! _is_workspace_mounted "${volumes_to_save}" "${project_path}"; then
                startup_cmd_session=$(_copy_local_script_to_container "${container_name}" "${docker_cmd}" "${startup_cmd_session}")
            fi
        fi

        _attach_session "${container_name}" "${docker_cmd}" "${startup_cmd_session}" \
            "${persist_to_save}" "${run_on_reattach}" "${detach}" "${has_tty}" \
            "Created; attaching (stop on exit)" \
            "Created; attaching (persist on exit)" \
            "Created; running startup command without interactive shell" \
            "Created container but no TTY detected; skip attach (no startup command)" \
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

    if [[ "${remove_on_exit}" == true ]]; then
        local image_to_remove_on_exit
        image_to_remove_on_exit="$(_container_image_name "${container_name}" "${docker_cmd}")"
        local tmp_vols=()
        while IFS=: read -r mount_type vol_name _; do
            [[ -z "${mount_type}" || "${mount_type}" != "volume" ]] && continue
            if [[ "${vol_name}" == "${container_name}."* ]]; then
                tmp_vols+=("${vol_name}")
            fi
        done < <(_docker_exec "${docker_cmd}" inspect --format '{{range .Mounts}}{{.Type}}:{{.Name}}:{{.Destination}}{{printf "\n"}}{{end}}' "${container_name}" 2>/dev/null)
    fi
    
    if _stop_container "${container_name}" "${docker_cmd}"; then
        if [[ "${remove_on_exit}" == true ]]; then
            if _remove_container "${container_name}" "${docker_cmd}" "true"; then
                for vol_name in "${tmp_vols[@]}"; do
                    _docker_exec "${docker_cmd}" volume rm "${vol_name}" >/dev/null 2>&1 || true
                done
                _remove_image_if_exists "${image_to_remove_on_exit}" "${docker_cmd}"
            fi
        fi
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
    _validate_container_name "${container_name}" "id ${container_arg}" || return 1

    local docker_cmd="${docker_cmd_override:-$(_get_config "${container_name}" "docker_cmd" "${FDEVC_DOCKER}")}"

    _container_exists "${container_name}" "${docker_cmd}" || { _msg_error "Container $(_format_container_title "${container_name}") not found"; return 1; }
    _stop_container "${container_name}" "${docker_cmd}"
}

_fdevc_rm() {
    local force=false delete_all=false container_arg="" docker_cmd_override=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            --all) delete_all=true; shift ;;
            --dkr) docker_cmd_override="$2"; shift 2 ;;
            *) container_arg="$1"; shift ;;
        esac
    done
    
    local container_name
    container_name="$(_resolve_container_name "${container_arg}")"
    _validate_container_name "${container_name}" "id ${container_arg}" || return 1

    local docker_cmd="${docker_cmd_override:-$(_get_config "${container_name}" "docker_cmd" "${FDEVC_DOCKER}")}"

    local config_json
    config_json=$(_load_config "${container_name}")
    local has_config=false
    [[ -n "${config_json}" && "${config_json}" != "{}" ]] && has_config=true

    local container_status
    container_status=$(_container_status "${container_name}" "${docker_cmd}")

    # Container missing - only config exists
    if [[ "${container_status}" == "missing" ]]; then
        if [[ "${has_config}" != true ]]; then
            _msg_error "Container $(_format_container_title "${container_name}") not found"
            return 1
        fi
        _msg_info "Container gone, removing config"
        _remove_config "${container_name}"
        _msg_success "Config deleted"
        return 0
    fi
    
    # Helper function to get volumes for removal
    _get_volumes_to_remove() {
        local volumes_config="$1" project_path="$2" container_name="$3"
        local volumes_to_remove=()
        if [[ -n "${volumes_config}" ]]; then
            local volume_list=()
            if [[ -n "${ZSH_VERSION-}" ]]; then
                IFS='|||' read -rA volume_list <<< "${volumes_config}"
            else
                IFS='|||' read -r -a volume_list <<< "${volumes_config}"
            fi
            for vol in "${volume_list[@]}"; do
                [[ -z "${vol}" ]] && continue
                # shellcheck disable=SC2155
                local normalized_vol=$(_normalize_volume_name "${vol}" "${container_name}" "${project_path}")
                local vol_source="${normalized_vol%%:*}"
                if [[ "${vol_source}" != /* && "${vol_source}" != ./* && "${normalized_vol}" == *:* ]]; then
                    volumes_to_remove+=("${vol_source}")
                fi
            done
        fi
        echo "${volumes_to_remove[@]}"
    }
    
    # Get volumes and image info
    local volumes_config project_path image_name default_image
    volumes_config=$(_get_config "${container_name}" "volumes" "")
    project_path=$(_get_config "${container_name}" "project_path" "")
    image_name="$(_container_image_name "${container_name}" "${docker_cmd}")"
    default_image=$(_get_default_image)
    
    local volumes_to_remove_arr=()
    if [[ -n "${volumes_config}" ]]; then
        local volumes_str
        volumes_str=$(_get_volumes_to_remove "${volumes_config}" "${project_path}" "${container_name}")
        if [[ -n "${volumes_str}" ]]; then
            if [[ -n "${ZSH_VERSION-}" ]]; then
                read -rA volumes_to_remove_arr <<< "${volumes_str}"
            else
                read -r -a volumes_to_remove_arr <<< "${volumes_str}"
            fi
        fi
    else
        while IFS=: read -r mount_type vol_name _; do
            [[ -z "${mount_type}" || "${mount_type}" != "volume" ]] && continue
            if [[ "${vol_name}" == "${container_name}."* ]]; then
                volumes_to_remove_arr+=("${vol_name}")
            fi
        done < <(_docker_exec "${docker_cmd}" inspect --format '{{range .Mounts}}{{.Type}}:{{.Name}}:{{.Destination}}{{printf "\n"}}{{end}}' "${container_name}" 2>/dev/null)
    fi
    
    # Determine what to delete based on container status and flags
    local is_running
    is_running=$([[ "${container_status}" == "running" ]] && echo "true" || echo "false")
    
    if [[ "${delete_all}" == true ]]; then
        # --all: Delete everything (stop if needed)
        if [[ "${is_running}" == "true" ]]; then
            if [[ "${force}" == true ]]; then
                _remove_container "${container_name}" "${docker_cmd}" "true" || return 1
            else
                _stop_container "${container_name}" "${docker_cmd}" || return 1
                _remove_container "${container_name}" "${docker_cmd}" || return 1
            fi
        else
            _remove_container "${container_name}" "${docker_cmd}" || return 1
        fi
        # Remove volumes
        if [[ ${#volumes_to_remove_arr[@]} -gt 0 ]]; then
            _msg_info "Removing volumes"
            for vol_name in "${volumes_to_remove_arr[@]}"; do
                if _docker_exec "${docker_cmd}" volume rm "${vol_name}" >/dev/null 2>&1; then
                    _msg_detail "Removed: ${vol_name}"
                else
                    _msg_detail "Failed to remove: ${vol_name}"
                fi
            done
        fi
        # Remove image (unless default)
        if [[ -n "${image_name}" && "${image_name}" != "${default_image}" ]]; then
            _remove_image_if_exists "${image_name}" "${docker_cmd}"
        fi
        # Remove config
        _remove_config "${container_name}"
        _msg_success "Container, volumes, image, and config deleted"
    elif [[ "${is_running}" == "true" ]]; then
        # Running: Stop, delete container and volumes (keep config/image)
        if [[ "${force}" == true ]]; then
            _remove_container "${container_name}" "${docker_cmd}" "true" || return 1
        else
            _stop_container "${container_name}" "${docker_cmd}" || return 1
            _remove_container "${container_name}" "${docker_cmd}" || return 1
        fi
        # Remove volumes
        if [[ ${#volumes_to_remove_arr[@]} -gt 0 ]]; then
            for vol_name in "${volumes_to_remove_arr[@]}"; do
                _msg_detail "Removing volume: ${vol_name}"
                _docker_exec "${docker_cmd}" volume rm "${vol_name}" >/dev/null 2>&1 || true
            done
        fi
        _msg_success "Container and volumes deleted (config preserved)"
    else
        # Stopped: Delete container and volumes (keep config/image)
        _remove_container "${container_name}" "${docker_cmd}" || return 1
        # Remove volumes
        if [[ ${#volumes_to_remove_arr[@]} -gt 0 ]]; then
            for vol_name in "${volumes_to_remove_arr[@]}"; do
                _msg_detail "Removing volume: ${vol_name}"
                _docker_exec "${docker_cmd}" volume rm "${vol_name}" >/dev/null 2>&1 || true
            done
        fi
        # Remove image (unless default)
        if [[ -n "${image_name}" && "${image_name}" != "${default_image}" ]]; then
            _remove_image_if_exists "${image_name}" "${docker_cmd}"
        fi
        # Keep config (user might want to restart)
        _msg_success "Container, volumes, and image deleted (config preserved)"
    fi
}

_fdevc_custom() {
    local target_file="fdevc.Dockerfile"
    local template_dockerfile="${SCRIPT_DIR}/Dockerfile"

    if [[ -f "${target_file}" ]]; then
        _msg_error "fdevc.Dockerfile already exists in current directory"
        return 1
    fi

    if [[ ! -f "${template_dockerfile}" ]]; then
        _msg_error "Template Dockerfile not found at: ${template_dockerfile}"
        return 1
    fi
    
    _msg_info "Copying template Dockerfile to ${target_file}"
    cp "${template_dockerfile}" "${target_file}" || { _msg_error "Failed to copy template"; return 1; }
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
    
    # Create project folder with fdevc_setup subfolder
    mkdir -p "${project_name}/fdevc_setup" || { _msg_error "Failed to create project"; return 1; }
    cd "${project_name}" || { _msg_error "Failed to enter project"; return 1; }
    
    _msg_success "Created project: ${project_name}"
    
    # Copy runnable.sh to fdevc_setup subfolder
    _msg_info "Creating fdevc_setup/runnable.sh"
    cp "${templates_dir}/runnable.sh" "./fdevc_setup/runnable.sh" || { _msg_error "Failed to create runnable.sh"; return 1; }
    chmod +x "./fdevc_setup/runnable.sh"
    _msg_success "Created fdevc_setup/runnable.sh"
    
    # Copy other files to project root
    _msg_info "Creating launch.sh"
    sed "s/__PROJECT__/${project_name}/g" "${templates_dir}/launch.sh" > "./launch.sh" || { _msg_error "Failed to create launch.sh"; return 1; }
    chmod +x "./launch.sh"
    _msg_success "Created launch.sh"
    
    _msg_info "Creating install_and_run script"
    sed "s/__PROJECT__/${project_name}/g" "${templates_dir}/install_and_run" > "./install_and_run" || { _msg_error "Failed to create install_and_run"; return 1; }
    chmod +x "./install_and_run"
    _msg_success "Created install_and_run"
    
    _msg_info "Creating README.md"
    sed -e "s/__PROJECT__/${project_name}/g" \
        "${templates_dir}/README.md" > "./README.md" || { _msg_error "Failed to create README.md"; return 1; }
    _msg_success "Created README.md"
    
    echo ""
    _msg_success "Runnable project created successfully!"
    echo -e "${_c_bold}${_c_cyan}📁 Current Location: ${_c_reset}${PWD}"
    echo -e "${_c_bold}${_c_cyan}📂 Structure:${_c_reset}"
    echo -e "  ${_c_dim}${project_name}/${_c_reset}"
    echo -e "  ${_c_dim}├── README.md${_c_reset}"
    echo -e "  ${_c_dim}├── install_and_run        # Installation script (curl one-liner)${_c_reset}"
    echo -e "  ${_c_dim}├── launch.sh              # Container launcher with predefined settings${_c_reset}"
    echo -e "  ${_c_dim}└── fdevc_setup/           # Folder mounted at /workspace/fdevc_setup in the container${_c_reset}"
    echo -e "  ${_c_dim}    └── runnable.sh        # Main script that runs inside the container${_c_reset}"
    echo ""
    echo -e "${_c_bold}${_c_cyan}Next steps:${_c_reset}"
    echo -e "  ${_c_bold}1. Replace${_c_reset} all ${_c_magenta}__USER__${_c_reset} with your ${_c_magenta}GitHub username${_c_reset} in the project"
    echo -e "  ${_c_bold}2. Edit${_c_reset} ${_c_yellow}fdevc_setup/runnable.sh${_c_reset} to add your setup commands, install tools, or run applications"
    echo -e "  ${_c_bold}3. Edit${_c_reset} ${_c_yellow}launch.sh${_c_reset} to change container configuration (ports, image, persistence mode, etc.)"
    echo -e "  ${_c_bold}4. Edit${_c_reset} ${_c_yellow}README.md${_c_reset} to match your project's needs, remove ${_c_magenta}TODO & REMOVE section${_c_reset} and add ${_c_magenta}Usage section${_c_reset}"
    echo -e "  ${_c_bold}5. Optional: Run${_c_reset} ${_c_cyan}fdevc custom${_c_reset} in the project to create a custom ${_c_yellow}./fdevc.Dockerfile${_c_reset} for more advanced configurations"
    echo -e "  ${_c_bold}6. Optional: Test${_c_reset} locally ${_c_cyan}./launch.sh${_c_reset}"
    echo -e "  ${_c_bold}7. Push${_c_reset} to GitHub and share: ${_c_green}curl -fsSL https://raw.githubusercontent.com/<user>/${project_name}/main/install_and_run | bash${_c_reset}"
}

_fdevc_help() {
    # Read and format help.txt with colors
    while IFS= read -r line; do
        # Title line with underline (first line)
        if [[ "${line}" =~ ^Fast\ Dev\ Container ]]; then
            echo -e "${_c_bold}${_c_cyan}${line}${_c_reset}"
        # Separator lines (=== or ---)
        elif [[ "${line}" =~ ^=+$ || "${line}" =~ ^-+$ ]]; then
            echo -e "${_c_dim}${line}${_c_reset}"
        # Section headers (ALL CAPS words)
        elif [[ "${line}" =~ ^[A-Z][A-Z\ ]+$ ]]; then
            echo -e "\n${_c_bold}${_c_yellow}${line}${_c_reset}"
        # Command names starting with 'fdevc'
        elif [[ "${line}" =~ ^fdevc ]]; then
            echo -e "\n${_c_bold}${_c_green}${line}${_c_reset}"
        # Options (indented lines starting with -)
        elif [[ "${line}" =~ ^[[:space:]]+-[a-z] || "${line}" =~ ^[[:space:]]+--[a-z] ]]; then
            echo -e "${_c_bold}${_c_blue}${line}${_c_reset}"
        # Deep indentation (descriptions, examples)
        elif [[ "${line}" =~ ^[[:space:]]{20,} ]]; then
            echo -e "${_c_dim}${line}${_c_reset}"
        # Empty lines
        elif [[ -z "${line}" ]]; then
            echo ""
        # Normal lines
        else
            echo "${line}"
        fi
    done < "${HELP_FILE}"
    echo ""  # Add trailing newline
}

_fdevc_ls() {
    # Get container names first
    local container_names
    container_names=$(_docker_exec "${FDEVC_DOCKER}" ps -a --filter "name=^fdevc\\." --format '{{.Names}}' 2>/dev/null)
    
    # For each container, get detailed info including full mounts JSON
    local output=""
    while IFS= read -r name; do
        [[ -z "${name}" ]] && continue
        local container_status image mounts_json socket_label created_at
        container_status=$(_docker_exec "${FDEVC_DOCKER}" ps -a --filter "name=^${name}$" --format '{{.Status}}' 2>/dev/null)
        image=$(_docker_exec "${FDEVC_DOCKER}" ps -a --filter "name=^${name}$" --format '{{.Image}}' 2>/dev/null)
        mounts_json=$(_docker_exec "${FDEVC_DOCKER}" inspect "${name}" --format '{{json .Mounts}}' 2>/dev/null)
        socket_label=$(_docker_exec "${FDEVC_DOCKER}" inspect "${name}" --format '{{.Config.Labels.fdevc.socket}}' 2>/dev/null)
        created_at=$(_docker_exec "${FDEVC_DOCKER}" inspect "${name}" --format '{{.Created}}' 2>/dev/null)
        output+="${name}|||${container_status}|||${image}|||${mounts_json}|||${socket_label}|||${created_at}"$'\n'
    done <<< "${container_names}"
    
    echo -n "${output}" | ${FDEVC_PYTHON} "${UTILS_PY}" list_containers "${CONFIG_FILE}"
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