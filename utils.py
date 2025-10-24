#!/usr/bin/env python3
import json
import os
import sys


def load_config(config_file, container_name):
    """Load configuration for a specific container."""
    try:
        with open(config_file) as f:
            data = json.load(f)
        cfg = data.get(container_name, {})
        print(json.dumps(cfg))
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        print('{}')


def get_config_value(key, default=''):
    """Extract a value from JSON config passed via stdin."""
    try:
        cfg = json.load(sys.stdin)
        val = cfg.get(key, default)
        if isinstance(val, list):
            print(' '.join(val))
        else:
            print(val)
    except (json.JSONDecodeError, KeyError, AttributeError):
        print(default)


def save_config(config_file, container_name, ports='', image='', docker_cmd='', project_path=''):
    """Save container configuration."""
    data = {}
    if os.path.exists(config_file):
        try:
            with open(config_file) as f:
                data = json.load(f)
        except (json.JSONDecodeError, IOError):
            pass

    if container_name not in data:
        data[container_name] = {}

    cfg = data[container_name]
    if ports:
        cfg['ports'] = [p if ':' in p else f'{p}:{p}' for p in ports.split() if p]
    if image:
        cfg['image'] = image
    if docker_cmd:
        cfg['docker_cmd'] = docker_cmd
    if project_path:
        cfg['project_path'] = project_path

    with open(config_file, 'w') as f:
        json.dump(data, f, indent=2, sort_keys=True)


def remove_config(config_file, container_name):
    """Remove container configuration."""
    if os.path.exists(config_file):
        try:
            with open(config_file) as f:
                data = json.load(f)
            data.pop(container_name, None)
            with open(config_file, 'w') as f:
                json.dump(data, f, indent=2, sort_keys=True)
        except (json.JSONDecodeError, IOError):
            pass


def list_containers(config_file, current_dir_container):
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
            with open(config_file, "r") as f:
                config_data = json.load(f)
        except (json.JSONDecodeError, IOError):
            pass

    # Merge: all containers from docker + config-only containers
    all_containers = {}
    for name in docker_containers:
        all_containers[name] = {"status": docker_containers[name], "in_docker": True}
    for name in config_data:
        if name not in all_containers:
            all_containers[name] = {"status": None, "in_docker": False}

    if not all_containers:
        print("No dev containers found.")
        sys.exit(0)

    # Print header
    print("{:<4}{:<30}{:<15}{:<20}".format("#", "NAME", "STATUS", "PORTS"))
    print("─" * 69)

    # Print containers
    for idx, name in enumerate(sorted(all_containers.keys()), 1):
        container_info = all_containers[name]
        cfg = config_data.get(name, {})
        ports = " ".join(cfg.get("ports", [])) or "·"
        
        # Determine status display
        if container_info["in_docker"]:
            status = container_info["status"]
            if "Up" in status:
                status_display = "● Running"
            else:
                status_display = "○ Stopped"
        else:
            status_display = "◌ Saved"
        
        print("{:<4}{:<30}{:<15}{:<20}".format(idx, name, status_display, ports))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: utils.py <command> [args...]", file=sys.stderr)
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == 'load_config':
        load_config(sys.argv[2], sys.argv[3])
    elif command == 'get_config_value':
        get_config_value(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else '')
    elif command == 'save_config':
        save_config(sys.argv[2], sys.argv[3], 
                   sys.argv[4] if len(sys.argv) > 4 else '',
                   sys.argv[5] if len(sys.argv) > 5 else '',
                   sys.argv[6] if len(sys.argv) > 6 else '',
                   sys.argv[7] if len(sys.argv) > 7 else '')
    elif command == 'remove_config':
        remove_config(sys.argv[2], sys.argv[3])
    elif command == 'list_containers':
        list_containers(sys.argv[2], sys.argv[3])
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
