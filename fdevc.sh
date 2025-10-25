: "${FDEVC_PYTHON:=python3}"
: "${FDEVC_DOCKER:=docker}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
: "${FDEVC_IMAGE:=${SCRIPT_DIR}/Dockerfile}"
CONFIG_FILE="${SCRIPT_DIR}/.dev_config.json"
UTILS_PY="${SCRIPT_DIR}/utils.py"
HELP_FILE="${SCRIPT_DIR}/help.txt"

_check_dependencies() {
    local missing=()
    local docker_base_cmd=$(echo "${FDEVC_DOCKER}" | awk '{print $1}')
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

_prepare_save_config_args() {
    local no_volume="$1" no_socket="$2" project_path="$3" socket_config="$4"
    local project_to_save="${project_path}"
    [[ "${no_volume}" == true ]] && project_to_save=""
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
_get_container_by_index() {
    local index="$1"
    local docker_output
    docker_output=$(_docker_exec "${FDEVC_DOCKER}" ps -a --filter "name=^fdevc\\." --format '{{.Names}}|||{{.Status}}|||{{.Image}}' 2>/dev/null)
    printf '%s\n' "${docker_output}" | ${FDEVC_PYTHON} "${UTILS_PY}" resolve_index "${CONFIG_FILE}" "${index}"
}

_load_config() {
    local container_name="$1"
    [[ ! -f "${CONFIG_FILE}" ]] && echo "{}" && return
    ${FDEVC_PYTHON} "${UTILS_PY}" load_config "${CONFIG_FILE}" "${container_name}" 2>/dev/null
}

_get_config_value() {
    local config="$1" key="$2" default="$3"
    local value=$(echo "${config}" | ${FDEVC_PYTHON} "${UTILS_PY}" get_config_value "${key}" "${default}" 2>/dev/null)
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
    local project_path="$5"
    local startup_cmd="$6"
    local socket_state="$7"

    mkdir -p "$(dirname "${CONFIG_FILE}")"
    ${FDEVC_PYTHON} "${UTILS_PY}" save_config "${CONFIG_FILE}" "${container_name}" "${ports}" "${image}" "${docker_cmd}" "${project_path}" "${startup_cmd}" "${socket_state}" 2>/dev/null
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
    local dockerfile_dir="$(dirname "${dockerfile}")"
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
    local docker_cmd_override="$4"
    local project_override="$5"
    local socket_override="$6"
    
    # Load config once
    local config=$(_load_config "${container_name}")
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

    local project_from_config="$(_get_config_value "${config}" "project_path" "__DEVCONF_NO_PROJECT__")"
    local project_path=""
    if [[ -n "${project_override}" ]]; then
        project_path="${project_override}"
    elif [[ "${project_from_config}" == "__DEVCONF_NO_PROJECT__" ]]; then
        project_path="$PWD"
    else
        project_path="${project_from_config}"
    fi

    local socket_from_config="$(_get_config_value "${config}" "socket" "__DEVCONF_NO_SOCKET__")"
    local socket_value=""
    if [[ -n "${socket_override}" ]]; then
        socket_value="${socket_override}"
    elif [[ "${socket_from_config}" == "__DEVCONF_NO_SOCKET__" ]]; then
        socket_value=""
    else
        socket_value="${socket_from_config}"
    fi

    local startup_cmd="$(_get_config_value "${config}" "startup_cmd" "")"
    
    # Convert Dockerfile to absolute path
    if [[ -f "${image}" ]]; then
        image="$(_absolute_path "${image}")"
    fi
    
    # Output as space-separated values
    echo "${ports}|${image}|${docker_cmd}|${project_path}|${startup_cmd}|${socket_value}|${config_present}"
}

_fdevc_start() {
    local container_arg="" ports_override="" image_override="" docker_cmd_override="" detach=false remove_on_exit=false
    local no_volume=false no_socket=false force_new=false
    local startup_cmd_once="" startup_cmd_save="" startup_cmd_save_flag=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p) ports_override="$2"; shift 2 ;;
            -i) image_override="$2"; shift 2 ;;
            --dkr) docker_cmd_override="$2"; shift 2 ;;
            --tmp) remove_on_exit=true; shift ;;
            -d) detach=true; shift ;;
            --no-v) no_volume=true; shift ;;
            --no-s) no_socket=true; shift ;;
            -c) startup_cmd_once="$2"; shift 2 ;;
            --c-s) startup_cmd_once="$2"; startup_cmd_save="$2"; startup_cmd_save_flag=true; shift 2 ;;
            --new) force_new=true; shift ;;
            *) 
                if [[ "${force_new}" == true ]]; then
                    _msg_error "Unknown argument: $1"
                    return 1
                fi
                container_arg="$1"
                shift
                ;;
        esac
    done

    if [[ "${remove_on_exit}" == true && "${detach}" == true ]]; then
        _msg_info "--tmp overrides -d; container will be stopped and removed."
        detach=false
    fi
    
    local overrides_supplied=false
    [[ -n "${ports_override}" || -n "${image_override}" || -n "${docker_cmd_override}" ]] && overrides_supplied=true

    # Determine container name based on mode
    local container_name
    if [[ "${force_new}" == true ]]; then
        container_name="fdevc.$(basename "$PWD").$(date +%s)"
    else
        container_name="$(_resolve_container_name "${container_arg}")"
        [[ -z "${container_name}" ]] && { _msg_error "No container found at index ${container_arg}. Run 'fdevc ls'."; return 1; }
    fi
    
    local socket_override_arg=""
    [[ "${no_socket}" == true ]] && socket_override_arg="false"

    # Merge config with overrides (force_new uses $PWD as project_path)
    local merge_project_path=""
    [[ "${force_new}" == true ]] && merge_project_path="$PWD"
    IFS='|' read -r ports image_config docker_cmd project_path startup_cmd_config socket_config config_present <<< "$(_merge_config "${container_name}" "${ports_override}" "${image_override}" "${docker_cmd_override}" "${merge_project_path}" "${socket_override_arg}")"
    local startup_cmd_session="${startup_cmd_once:-${startup_cmd_config}}"
    local startup_cmd_to_save="${startup_cmd_config}"
    if [[ "${startup_cmd_save_flag}" == true ]]; then
        startup_cmd_to_save="${startup_cmd_save}"
    fi
    
    # Resolve image (build from Dockerfile if needed)
    local image=$(_resolve_image "${image_config}" "${docker_cmd}" "${container_name}") || { _msg_error "Failed to resolve image"; return 1; }
    
    # Check if container exists (skip for force_new)
    local container_exists=false
    if [[ "${force_new}" != true ]] && _container_exists "${container_name}" "${docker_cmd}"; then
        container_exists=true
    fi

    if [[ "${container_exists}" == true && "${overrides_supplied}" == true ]]; then
        _msg_info "Removing existing '${container_name}' to apply overrides..."
        if ! _docker_exec "${docker_cmd}" rm -f "${container_name}" >/dev/null 2>&1; then
            _msg_error "Failed to recreate container with overrides"
            return 1
        fi
        container_exists=false
    fi

    local exec_status=0

    if [[ "${container_exists}" == true ]]; then
        _msg_info "Starting '${container_name}'..."
        [[ -n "${ports}" ]] && _msg_detail "Ports: ${ports}"
        _msg_docker_cmd "${docker_cmd} start ${container_name}"
        _docker_exec "${docker_cmd}" start "${container_name}" >/dev/null 2>&1 || { _msg_error "Failed to start"; return 1; }
        _msg_success "Attaching..."
        if [[ "${remove_on_exit}" != true ]]; then
            IFS='|' read -r project_to_save socket_to_save <<< "$(_prepare_save_config_args "${no_volume}" "${no_socket}" "${project_path}" "${socket_config}")"
            if [[ "${startup_cmd_save_flag}" == true || "${config_present}" != "true" ]]; then
                _save_config "${container_name}" "${ports}" "${image_config}" "${docker_cmd}" "${project_to_save}" "${startup_cmd_to_save}" "${socket_to_save}"
            fi
        fi
        if [[ -n "${startup_cmd_session}" ]]; then
            _docker_exec "${docker_cmd}" exec -it -w /workspace "${container_name}" bash -lc "${startup_cmd_session}; exec bash"
        else
            _docker_exec "${docker_cmd}" exec -it -w /workspace "${container_name}" bash
        fi
        exec_status=$?
    else
        _msg_info "Creating '${container_name}' [${image}]"
        [[ -n "${ports}" ]] && _msg_detail "Ports: ${ports}"
        
        local port_flags_arr=()
        while IFS= read -r line; do port_flags_arr+=("$line"); done < <(_build_port_flags "${ports}")

        local run_args=(-d --name "${container_name}")
        if [[ "${no_volume}" != true ]]; then
            run_args+=(-v "${project_path}:/workspace")
        fi
        if [[ "${no_socket}" != true ]]; then
            run_args+=(-v /var/run/docker.sock:/var/run/docker.sock)
        fi
        run_args+=("${port_flags_arr[@]}" "${image}")

        _msg_docker_cmd "${docker_cmd} run ${run_args[*]}"
        _docker_exec "${docker_cmd}" run "${run_args[@]}" || { _msg_error "Failed to create"; return 1; }
        if [[ "${remove_on_exit}" != true ]]; then
            IFS='|' read -r project_to_save socket_to_save <<< "$(_prepare_save_config_args "${no_volume}" "${no_socket}" "${project_path}" "${socket_config}")"
            _save_config "${container_name}" "${ports}" "${image_config}" "${docker_cmd}" "${project_to_save}" "${startup_cmd_to_save}" "${socket_to_save}"
        fi

        _msg_success "Created, attaching..."
        if [[ -n "${startup_cmd_session}" ]]; then
            _docker_exec "${docker_cmd}" exec -it -w /workspace "${container_name}" bash -lc "${startup_cmd_session}; exec bash"
        else
            _docker_exec "${docker_cmd}" exec -it -w /workspace "${container_name}" bash
        fi
        exec_status=$?
    fi

    if [[ "${detach}" == true ]]; then
        _msg_info "Detaching '${container_name}'..."
    else
        _msg_info "Stopping '${container_name}'..."
        _msg_docker_cmd "${docker_cmd} stop ${container_name}"
        if _docker_exec "${docker_cmd}" stop "${container_name}" >/dev/null 2>&1; then
            _msg_success "Stopped"
            if [[ "${remove_on_exit}" == true ]]; then
                _msg_info "Removing '${container_name}'..."
                _msg_docker_cmd "${docker_cmd} rm -f ${container_name}"
                if _docker_exec "${docker_cmd}" rm -f "${container_name}" >/dev/null 2>&1; then
                    _msg_success "Removed"
                else
                    _msg_error "Failed to remove '${container_name}'"
                fi
            fi
        else
            _msg_error "Failed to stop '${container_name}'"
        fi
    fi

    return "${exec_status}"
}

_fdevc_new() {
    # Wrapper that creates a new timestamped container
    _fdevc_start --new "$@"
}

_fdevc_stop() {
    local container_arg="" docker_cmd_override=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dkr) docker_cmd_override="$2"; shift 2 ;;
            *) container_arg="$1"; shift ;;
        esac
    done

    local container_name="$(_resolve_container_name "${container_arg}")"
    [[ -z "${container_name}" ]] && { _msg_error "No container found at index ${container_arg}. Run 'fdevc ls'."; return 1; }

    local docker_cmd="${docker_cmd_override:-$(_get_config "${container_name}" "docker_cmd")}"
    docker_cmd="${docker_cmd:-${FDEVC_DOCKER}}"

    _msg_info "Stopping '${container_name}'..."
    _container_exists "${container_name}" "${docker_cmd}" || { _msg_error "Container '${container_name}' not found"; return 1; }
    _msg_docker_cmd "${docker_cmd} stop ${container_name}"
    _docker_exec "${docker_cmd}" stop "${container_name}" >/dev/null 2>&1 && _msg_success "Stopped" || { _msg_error "Failed"; return 1; }
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
    
    local container_name="$(_resolve_container_name "${container_arg}")"
    [[ -z "${container_name}" ]] && { _msg_error "No container found at index ${container_arg}. Run 'fdevc ls'."; return 1; }

    local docker_cmd="${docker_cmd_override:-$(_get_config "${container_name}" "docker_cmd")}"
    docker_cmd="${docker_cmd:-${FDEVC_DOCKER}}"

    local config_json=$(_load_config "${container_name}")
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

    # Remove container
    if [[ "${force}" == true ]]; then
        _msg_info "Force removing '${container_name}'..."
        _msg_docker_cmd "${docker_cmd} rm -f ${container_name}"
        _docker_exec "${docker_cmd}" rm -f "${container_name}" >/dev/null 2>&1 || { _msg_error "Failed to remove"; return 1; }
    else
        _msg_info "Stopping and removing '${container_name}'..."
        _msg_docker_cmd "${docker_cmd} stop ${container_name}"
        _docker_exec "${docker_cmd}" stop "${container_name}" >/dev/null 2>&1 || { _msg_error "Failed to stop. Use -f to force."; return 1; }
        _msg_docker_cmd "${docker_cmd} rm ${container_name}"
        _docker_exec "${docker_cmd}" rm "${container_name}" >/dev/null 2>&1 || { _msg_error "Failed to remove"; return 1; }
    fi
    
    # Handle config
    if [[ "${with_config}" == true ]]; then
        _remove_config "${container_name}"
        _msg_success "Container and config deleted"
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

_fdevc_help() {
    cat "${HELP_FILE}"
}

_fdevc_ls() {
    _docker_exec "${FDEVC_DOCKER}" ps -a --filter "name=^fdevc\\." --format '{{.Names}}|||{{.Status}}|||{{.Image}}' 2>/dev/null | \
    ${FDEVC_PYTHON} "${UTILS_PY}" list_containers "${CONFIG_FILE}"
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