#!/usr/bin/env bash
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

log() {
	printf '%s\n' "$1"
}

log_warn() {
	printf 'Warning: %s\n' "$1" >&2
}

die() {
	printf 'Error: %s\n' "$1" >&2
	exit 1
}

APT_UPDATED=0

apt_install() {
	local package="$1"
	if ! command -v apt-get >/dev/null 2>&1; then
		die "apt-get not available to install ${package}"
	fi

	if ((APT_UPDATED == 0)); then
		if ((EUID == 0)); then
			apt-get update
		else
			if ! command -v sudo >/dev/null 2>&1; then
				die "sudo required to install ${package}"
			fi
			sudo apt-get update
		fi
		APT_UPDATED=1
	fi

	if ((EUID == 0)); then
		apt-get install -y "${package}"
	else
		sudo apt-get install -y "${package}"
	fi
}

ensure_shellcheck() {
	if command -v shellcheck >/dev/null 2>&1; then
		return
	fi

	log "Installing shellcheck..."
	if command -v apt-get >/dev/null 2>&1; then
		apt_install shellcheck
	elif command -v brew >/dev/null 2>&1; then
		brew install shellcheck
	else
		die "Unable to install shellcheck (supported package managers: apt-get, brew)"
	fi
}

ensure_shfmt() {
	if command -v shfmt >/dev/null 2>&1; then
		return
	fi

	log "Installing shfmt..."
	if command -v apt-get >/dev/null 2>&1; then
		apt_install shfmt
	elif command -v brew >/dev/null 2>&1; then
		brew install shfmt
	elif command -v go >/dev/null 2>&1; then
		local gobin="${GOBIN:-${HOME}/go/bin}"
		mkdir -p "${gobin}"
		GO111MODULE=on GOBIN="${gobin}" go install mvdan.cc/sh/v3/cmd/shfmt@latest
		export PATH="${gobin}:${PATH}"
	else
		die "Unable to install shfmt (supported: apt-get, brew, go)"
	fi

	command -v shfmt >/dev/null 2>&1 || die "shfmt installation failed"
}

PYTHON_BIN=""

detect_python() {
	if command -v python3 >/dev/null 2>&1; then
		PYTHON_BIN="$(command -v python3)"
	elif command -v python >/dev/null 2>&1; then
		PYTHON_BIN="$(command -v python)"
	else
		die "Python interpreter not found"
	fi
}

ensure_pip() {
	if ! "${PYTHON_BIN}" -m pip --version >/dev/null 2>&1; then
		log "Bootstrapping pip..."
		"${PYTHON_BIN}" -m ensurepip --upgrade >/dev/null 2>&1 || die "Failed to bootstrap pip"
	fi
}

ensure_python_tools() {
	local missing=()

	if ! "${PYTHON_BIN}" -m ruff --version >/dev/null 2>&1; then
		missing+=("ruff")
	fi
	if ! "${PYTHON_BIN}" -m mypy --version >/dev/null 2>&1; then
		missing+=("mypy")
	fi

	if ((${#missing[@]} > 0)); then
		ensure_pip
		log "Installing Python tools: ${missing[*]}"
		"${PYTHON_BIN}" -m pip install --upgrade --user "${missing[@]}"
	fi
}

ensure_shellcheck
ensure_shfmt
detect_python
ensure_python_tools

SHFMT_FILES=(
	install
	linter.sh
	templates/install_and_run
	templates/launch.sh
	templates/runnable.sh
)

SHELLCHECK_FILES=(
	install
	fdevc.sh
	linter.sh
	templates/install_and_run
	templates/launch.sh
	templates/runnable.sh
)

log "Shell Formatting..."
for script in "${SHFMT_FILES[@]}"; do
	if ! shfmt -w "${script}"; then
		log_warn "shfmt skipped ${script} (unsupported syntax)"
	fi
done

log "Shell Linting..."
for script in "${SHELLCHECK_FILES[@]}"; do
	shellcheck "${script}"
done

log "Python Formatting..."
"${PYTHON_BIN}" -m ruff format utils.py

log "Python Linting..."
"${PYTHON_BIN}" -m ruff check utils.py --fix
"${PYTHON_BIN}" -m mypy utils.py --strict
