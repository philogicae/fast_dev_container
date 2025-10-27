# __PROJECT__

fdevc runnable project powered by [fast_dev_container](https://github.com/philogicae/fast_dev_container).

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/__USER__/__PROJECT__/main/install_and_run | bash
```

**Requirements:** Docker (or Podman/compatible), Python 3, and Git.

> If not already present, it will automatically install [fast_dev_container](https://github.com/philogicae/fast_dev_container).

## Structure

- **`install_and_run`** - Installation script that ensures `fdevc` is available, clones this repository, and runs `launch.sh`.
- **`launch.sh`** - Helper script to launch a container using `fdevc` with predefined settings. Edit the configuration variables at the top to customize ports, image, persistence, etc.
- **`runnable.sh`** - The main script that runs inside the container.

## TODO

1. **Replace** `__USER__` with your GitHub username in all files.
2. **Edit** `runnable.sh` to add your setup commands, install tools, or run applications.
3. **Edit** `launch.sh` to change container configuration (ports, image, persistence mode, etc.).
4. **Edit** `README.md` to match your project's needs.
5. **Optional:** Run `fdevc custom` to create a custom ./fdevc.Dockerfile that you can edit and commit for more advanced configurations.