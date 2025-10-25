```bash
    ______           __     ____               ______            __        _                
   / ____/___ ______/ /_   / __ \___ _   __   / ____/___  ____  / /_____ _(_)___  ___  _____
  / /_  / __ `/ ___/ __/  / / / / _ \ | / /  / /   / __ \/ __ \/ __/ __ `/ / __ \/ _ \/ ___/
 / __/ / /_/ (__  ) /_   / /_/ /  __/ |/ /  / /___/ /_/ / / / / /_/ /_/ / / / / /  __/ /    
/_/    \__,_/____/\__/  /_____/\___/|___/   \____/\____/_/ /_/\__/\__,_/_/_/ /_/\___/_/     
```

Lightweight helpers for repeatable dev environments.

Create or attach a container for the current directory, then shut it down automatically when you exit.

## Installation

**Quick Install (Recommended):**
```bash
curl -fsSL https://raw.githubusercontent.com/philogicae/fast_dev_container/main/install | bash
```

**Manual Install:**
```bash
git clone https://github.com/philogicae/fast_dev_container.git ~/.fdevc
echo 'source ~/.fdevc/fdevc.sh' >> ~/.bashrc  # or ~/.zshrc
source ~/.bashrc  # or ~/.zshrc
```

**Requirements:** Docker (or Podman/compatible), Python 3, and Git.

## Usage

```bash
# Attach to/create a project container. Stops on exit unless -d.
fdevc [index|name] [OPTIONS]
# Or explicitly:
fdevc start [index|name] [OPTIONS]

# Create a timestamped container for the current directory.
fdevc new [OPTIONS]

# Stop a running container.
fdevc stop [index|name] [--dkr CMD]

# Stop and remove a container; add --all to delete saved config.
fdevc rm [index|name] [-f] [--all] [--dkr CMD]

# Copy template Dockerfile to current directory as fdevc.Dockerfile.
fdevc custom

# Show all fdevc containers (● running, ○ stopped, ◌ saved).
fdevc ls

# Show detailed help
fdevc [-h|--help]
```

**Options for fdevc (or fdevc start) and fdevc new:**
- `-p PORTS` - Port mappings (space-separated, e.g., "8080 3000:3001")
- `-i IMAGE|DOCKERFILE` - Docker image or path to Dockerfile
- `--dkr CMD` - Use alternative container runtime (e.g., podman)
- `-c CMD` - Run command once on attach (not saved)
- `--c-s CMD` - Run command on attach and save for future sessions
- `-d` - Detach mode (keep container running after exit)
- `--tmp` - Temporary mode (remove container on exit, overrides -d)
- `--no-v` - Skip volume mount (no project directory access)
- `--no-s` - Skip Docker socket mount (no nested containers)

**Status indicators:** ● running · ○ stopped · ◌ saved

## Examples

```bash
# Start container for current directory
fdevc

# Start with port mappings (space-separated ports to expose or host:container)
fdevc -p "8080:80 3000"

# Start with custom image
fdevc -i ubuntu:22.04

# Start with startup command
# Run command once on attach (not saved)
fdevc -c "npm run dev"
# Run command on attach and save for future sessions
fdevc --c-s "npm run dev"

# Create temporary test environment without volume mount
fdevc new --tmp --no-v

# Start by index from fdevc ls
fdevc 1

# Use Podman instead of Docker
fdevc --dkr podman
```

## Config

> Settings saved to `~/.fdevc/.dev_config.json`.

**Local Dockerfile:** If `fdevc.Dockerfile` exists in the current directory, it will be used by default instead of the global template. Use `fdevc custom` to create one.

Override default values with environment variables:
```bash
export FDEVC_PYTHON="python3" # Path/interpreter for Python
export FDEVC_DOCKER="podman" # Docker, Podman, containerd
export FDEVC_IMAGE="/path/to/Dockerfile" # Path to a Dockerfile
export FDEVC_IMAGE="debian:13-slim" # Docker image
```