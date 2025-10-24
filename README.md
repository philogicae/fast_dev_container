# Fast Dev Container

Persistent development container management with auto-config and multi-project support.

## Installation

Add to `~/.bashrc` or `~/.zshrc`:
```bash
source /path/to/fdevc.sh
```

**Requirements:** Docker/Podman + Python3

## Usage

```bash
dev_start                              # Start current directory container
dev_start -i node:latest -p "3000"     # Custom image + ports
dev_start 1                            # Start by index
dev_stop                               # Stop current directory container
dev_stop 1                             # Stop by index
dev_list                               # List all containers
dev_rm 1 --with-config                 # Remove container + config
```

## Commands

- `dev_start [index|name]` - Start/create container
- `dev_stop [index|name]` - Stop container
- `dev_rm [index|name]` - Remove container
- `dev_list` - List containers (● running, ○ stopped, ◌ saved)
- `dev_help` - Show help

**Flags:** `-p PORTS`, `-i IMAGE|Dockerfile`, `-c docker|podman`, `-f`, `--with-config`

## Features

- Auto-saves config (ports, image, paths) on creation
- Port normalization: `3000` → `3000:3000`
- Dockerfile auto-build with caching
- Index-based container switching
- Works with Docker, Podman, containerd
- Includes full-stack Dockerfile (Debian 12, Python 3.13, Node.js 22, Rust, build tools)

## Config

> Settings saved to `.dev_config.json`.

Override default values with environment variables:
```bash
export FAST_DEV_CONTAINER_PYTHON="python3" # Path/interpreter for Python
export FAST_DEV_CONTAINER_DOCKER="podman" # Docker, Podman, containerd
export FAST_DEV_CONTAINER_IMAGE="/path/to/Dockerfile" # Path to a Dockerfile
export FAST_DEV_CONTAINER_IMAGE="debian:bookworm-slim" # Docker image
```