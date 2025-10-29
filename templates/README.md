# __PROJECT__

One-liner to install & run a `fdevc runnable project` for __PROJECT__ powered by [fdevc](https://github.com/philogicae/fast_dev_container)

[![Curl](https://img.shields.io/badge/curl-required-orange)](https://curl.se/)
[![Git](https://img.shields.io/badge/git-required-orange)](https://git-scm.com/)
[![Docker](https://img.shields.io/badge/docker-required-orange)](https://www.docker.com/get-started/)
[![Python](https://img.shields.io/badge/python-3.10%2B-blue)](https://www.python.org/downloads/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/__USER__/__PROJECT__)

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/__USER__/__PROJECT__/main/install_and_run | bash
```

> If not already present, it will automatically install [fdevc](https://github.com/philogicae/fast_dev_container)

## Structure

```
__PROJECT__/
├── README.md
├── install_and_run        # Installation script (curl one-liner)
├── launch.sh              # Container launcher with predefined settings
└── fdevc_setup/
    └── runnable.sh        # Main script that runs inside the container
```

- **`install_and_run`** - Installation script that ensures `fdevc` is available, clones this repository, and runs `launch.sh`.
- **`launch.sh`** - Helper script to launch a container using `fdevc` with predefined settings. Edit the configuration variables at the top to customize ports, image, persistence, etc.
- **`fdevc_setup/runnable.sh`** - The main script that runs inside the container. The `fdevc_setup` folder is mounted to `/workspace` in the container.

# TODO & REMOVE (for runnable project creators)

1. **Replace** `__USER__` with your GitHub username in the Quick Install section above.
2. **Edit** `fdevc_setup/runnable.sh` to add your setup commands, install tools, or run applications.
3. **Edit** `launch.sh` to change container configuration (ports, image, persistence mode, etc.).
4. **Edit** `README.md` to match your project's needs and remove this section.
5. **Optional:** Run `fdevc custom` in the project root to create a custom ./fdevc.Dockerfile that you can edit and commit for more advanced configurations.
6. **Optional:** Add an `## Usage` section to explain how to use the project.