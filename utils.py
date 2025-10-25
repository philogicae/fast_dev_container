#!/usr/bin/env python3
import json
import os
import sys

COLOR_RESET = "\033[0m"
COLOR_BOLD = "\033[1m"
COLOR_DIM = "\033[2m"
COLOR_CYAN = "\033[96m"
COLOR_GREEN = "\033[92m"
COLOR_YELLOW = "\033[93m"


def load_config(config_file, container_name):
    """Load configuration for a specific container."""
    try:
        with open(config_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        cfg = data.get(container_name, {})
        print(json.dumps(cfg))
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        print("{}")


def get_config_value(key, default=""):
    """Extract a value from JSON config passed via stdin."""
    try:
        cfg = json.load(sys.stdin)
        val = cfg.get(key, default)
        if isinstance(val, list):
            print(" ".join(val))
        else:
            print(val)
    except (json.JSONDecodeError, KeyError, AttributeError):
        print(default)


def save_config(
    config_file,
    container_name,
    ports="",
    image="",
    docker_cmd="",
    project_path="",
    startup_cmd="",
    socket_state=None,
):
    """Save container configuration."""
    data = {}
    if os.path.exists(config_file):
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError):
            pass

    if container_name not in data:
        data[container_name] = {}

    cfg = data[container_name]
    if ports:
        cfg["ports"] = [p if ":" in p else f"{p}:{p}" for p in ports.split() if p]
    if image:
        cfg["image"] = image
    if docker_cmd:
        cfg["docker_cmd"] = docker_cmd
    if project_path is not None:
        cfg["project_path"] = project_path
    if startup_cmd:
        cfg["startup_cmd"] = startup_cmd
    else:
        cfg.pop("startup_cmd", None)

    if socket_state is not None:
        socket_value = str(socket_state).strip().lower()
        if socket_value in {"true", "false"}:
            cfg["socket"] = socket_value == "true"
        else:
            cfg.pop("socket", None)

    with open(config_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)


def remove_config(config_file, container_name):
    """Remove container configuration."""
    if os.path.exists(config_file):
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            data.pop(container_name, None)
            with open(config_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, sort_keys=True)
        except (json.JSONDecodeError, OSError):
            pass


def list_containers(config_file):
    """List all containers with their status and configuration."""
    # Read container data from stdin
    docker_containers = {}
    for line in sys.stdin:
        if line.strip():
            parts = line.strip().split("|||")
            if len(parts) >= 2:
                name, status = parts[0], parts[1]
                docker_containers[name] = status

    # Load config
    config_data = {}
    if config_file and os.path.exists(config_file):
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                config_data = json.load(f)
        except (json.JSONDecodeError, OSError):
            pass

    # Merge: all containers from docker + config-only containers
    all_containers = {}
    for name, status in docker_containers.items():
        all_containers[name] = {"status": status, "in_docker": True}
    for name in config_data:
        if name not in all_containers:
            all_containers[name] = {"status": None, "in_docker": False}

    if not all_containers:
        print("No dev containers found.")
        sys.exit(0)

    rows = []
    for idx, name in enumerate(sorted(all_containers.keys()), 1):
        container_info = all_containers[name]
        cfg = config_data.get(name, {})
        ports = " ".join(cfg.get("ports", [])) or ""

        # Determine status display
        if container_info["in_docker"]:
            status = container_info["status"]
            if "Up" in status:
                status_display = "● Running"
            else:
                status_display = "○ Stopped"
        else:
            status_display = "◌ Saved"

        rows.append((str(idx), name, status_display, ports))

    idx_width = max(len("#"), max(len(row[0]) for row in rows))
    name_width = max(len("NAME"), max(len(row[1]) for row in rows))
    status_width = max(len("STATUS"), max(len(row[2]) for row in rows))
    ports_width = max(len("PORTS"), max(len(row[3]) for row in rows))

    header_text = f"{'#':<{idx_width}}  {'NAME':<{name_width}}  {'STATUS':<{status_width}}  {'PORTS':<{ports_width}}"
    print(f"{COLOR_BOLD}{COLOR_CYAN}{header_text}{COLOR_RESET}")
    print(f"{COLOR_DIM}─{COLOR_RESET}" * len(header_text))

    for row in rows:
        idx, name, status, ports = row
        if "●" in status:
            status_colored = f"{COLOR_GREEN}{status}{COLOR_RESET}"
        elif "○" in status:
            status_colored = f"{COLOR_YELLOW}{status}{COLOR_RESET}"
        else:
            status_colored = f"{COLOR_DIM}{status}{COLOR_RESET}"
        name_colored = f"{COLOR_BOLD}{name}{COLOR_RESET}"
        ports_colored = f"{COLOR_DIM}{ports}{COLOR_RESET}" if ports else ""
        print(
            f"{idx:<{idx_width}}  {name_colored:<{name_width + len(COLOR_BOLD) + len(COLOR_RESET)}}  {status_colored:<{status_width + len(COLOR_GREEN) + len(COLOR_RESET)}}  {ports_colored}"
        )


def resolve_index(config_file, index_str):
    """Resolve a container index against docker and config entries."""
    try:
        index = int(index_str)
        if index <= 0:
            raise ValueError
    except ValueError:
        print("")
        return

    docker_containers = {}
    for line in sys.stdin:
        if line.strip():
            parts = line.strip().split("|||")
            if len(parts) >= 1:
                docker_containers[parts[0]] = True

    config_data = {}
    if config_file and os.path.exists(config_file):
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                config_data = json.load(f)
        except (json.JSONDecodeError, OSError):
            pass

    combined_names = sorted(set(docker_containers.keys()) | set(config_data.keys()))

    if 1 <= index <= len(combined_names):
        print(combined_names[index - 1])
    else:
        print("")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: utils.py <command> [args...]", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]
    if command == "load_config":
        load_config(sys.argv[2], sys.argv[3])
    elif command == "get_config_value":
        get_config_value(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
    elif command == "save_config":
        save_config(
            sys.argv[2],
            sys.argv[3],
            sys.argv[4] if len(sys.argv) > 4 else "",
            sys.argv[5] if len(sys.argv) > 5 else "",
            sys.argv[6] if len(sys.argv) > 6 else "",
            sys.argv[7] if len(sys.argv) > 7 else "",
            sys.argv[8] if len(sys.argv) > 8 else "",
            sys.argv[9] if len(sys.argv) > 9 else None,
        )
    elif command == "remove_config":
        remove_config(sys.argv[2], sys.argv[3])
    elif command == "list_containers":
        list_containers(sys.argv[2])
    elif command == "resolve_index":
        if len(sys.argv) < 4:
            print("")
        else:
            resolve_index(sys.argv[2], sys.argv[3])
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
