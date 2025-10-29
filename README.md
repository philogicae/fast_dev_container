![Fast Dev Container](banner.png)

Lightweight CLI to manage fast & repeatable `dev environments` and `runnable projects`

Create and manage vm-like dev containers for any directory in seconds.

[![Curl](https://img.shields.io/badge/curl-required-orange)](https://curl.se/)
[![Git](https://img.shields.io/badge/git-required-orange)](https://git-scm.com/)
[![Docker](https://img.shields.io/badge/docker-required-orange)](https://www.docker.com/get-started/)
[![Python](https://img.shields.io/badge/python-3.10%2B-blue)](https://www.python.org/downloads/)
[![Actions status](https://github.com/philogicae/fast_dev_container/actions/workflows/ci-cd.yml/badge.svg?cache-control=no-cache)](https://github.com/philogicae/fast_dev_container/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/philogicae/fast_dev_container)

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

## Usage

```bash
fdevc [id|name] [OPTIONS]     # Create/start/attach container (auto-stop on exit unless -d)
fdevc start [id|name]         # Explicit alias for fdevc
fdevc new [OPTIONS]           # Create timestamped container for parallel environments
fdevc vm [OPTIONS]            # Create VM-like container (no volume/socket mounts)
fdevc stop [id|name]          # Stop running container without removing
fdevc rm [id|name] [OPTIONS]  # Remove container+volumes (--all to remove everything)
fdevc ls                      # List all containers with status and configuration
fdevc config [--rm] [id|name] # Show/manage saved configs
fdevc custom                  # Copy template Dockerfile as fdevc.Dockerfile
fdevc gen <name>              # Create shareable fdevc runnable project
fdevc -h, --help              # Show detailed help message
```

**Common options:**
- `-i IMAGE|DOCKERFILE` - Custom image or Dockerfile path
- `-p "8080 3000:3001"` - Port mappings (space-separated)
- `-v "/data:/data"` - Volume mounts (can be repeated)
- `-c CMD` / `--c-s CMD` - Run command on attach (--c-s saves for future)
- `--cp ID|NAME` - Copy config from container
- `-n BASENAME` - Custom basename (collision-checked)
- `-d` / `--tmp` - Persist on exit / Remove on exit
- `-f, --force` - Recreate if config differs
- `--dkr podman` - Use alternative runtime
- `--no-dir` / `--no-v-dir` / `--no-s` - No project dir / Skip auto-mount / Skip socket

## Examples

```bash
fdevc                              # Start/attach container for current dir
fdevc -p "8080:80 3000"            # With port mappings
fdevc -i ubuntu:22.04              # With custom image
fdevc -v "/data:/data"             # With custom volume mount (host path)
fdevc -v "mydata:/app/data"        # With named volume (virtual volume)
fdevc --c-s "npm run dev"          # With saved startup command
fdevc --cp 1 -n myproject          # Copy config from container #1, use custom name
fdevc new --tmp --no-dir           # Temporary isolated environment (no project)
fdevc new -n test-env              # Create named container (no timestamp)
fdevc vm -i debian:13-slim -n dev  # VM-like container with custom name
fdevc vm -v "data:/data"           # VM with named volume (no project dir/socket)
fdevc gen my-project               # Create shareable fdevc runnable for my-project
fdevc ls                           # List all (use id to start: fdevc 1)
fdevc --dkr podman                 # Use Podman instead of Docker
```

## Configuration

Settings are automatically saved to `~/.fdevc/.fdevc_config.json`.

**Local Dockerfile:**
If `fdevc.Dockerfile` exists in current directory, it will be used by default instead of the global template. Use `fdevc custom` to create one.

**Environment Variables:**
```bash
export FDEVC_PYTHON="python3"         # Python interpreter (default: python3)
export FDEVC_DOCKER="podman"          # Container runtime (default: docker)
export FDEVC_IMAGE="debian:13-slim"   # Default image or Dockerfile path
```

## Tips

- Use `--tmp` for one-off experiments that should be cleaned up automatically
- Use `-d` (detach) to keep containers running after exit for long-running services
- Use `--no-dir` for portable containers that don't depend on a project directory
- Copy configs with `--cp` to quickly spin up similar environments
- Use `fdevc gen` to create shareable runnable projects others can install with curl

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a history of changes to this project.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.