#!/usr/bin/env python3

import json
import os
import random
import re
import sys
from datetime import datetime, timezone

COLOR_RESET = "\033[0m"
COLOR_BOLD = "\033[1m"
COLOR_DIM = "\033[2m"
COLOR_CYAN = "\033[96m"
COLOR_BLUE = "\033[94m"
COLOR_MAGENTA = "\033[95m"
COLOR_GREEN = "\033[92m"
COLOR_YELLOW = "\033[93m"
COLOR_RED = "\033[91m"
COLOR_PINK = "\033[38;5;213m"
COLOR_ORANGE = "\033[38;5;208m"

ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*m")


def visible_length(text):
    """Return the printable length of text without ANSI escape codes."""
    return len(ANSI_ESCAPE_RE.sub("", text))


def pad_to_width(text, target_width):
    """Pad a text (with ANSI codes) to the target visible width."""
    extra = target_width - visible_length(text)
    return f"{text}{' ' * extra}" if extra > 0 else text


def collapse_home_path(path):
    """Replace a leading HOME directory with ~ for display."""
    if not path:
        return path
    home = os.path.expanduser("~")
    try:
        expanded = os.path.expanduser(path)
        absolute = os.path.abspath(expanded)
    except (TypeError, ValueError, OSError):
        return path
    home_norm = os.path.normpath(home)
    absolute_norm = os.path.normpath(absolute)
    if absolute_norm == home_norm:
        return "~"
    prefix = home_norm + os.sep
    if absolute_norm.startswith(prefix):
        return "~" + absolute_norm[len(home_norm) :]
    return path


def format_created_timestamp(raw):
    """Format raw creation string into 'YYYY-MM-DD HH:MM:SS'."""
    if not raw:
        return ""

    text = raw.strip()
    if not text:
        return ""

    dt = None

    # Try ISO-like formats first
    iso_candidate = text
    if iso_candidate.endswith("Z") and "T" in iso_candidate:
        iso_candidate = iso_candidate.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(iso_candidate)
    except ValueError:
        dt = None

    # Fallback for docker format: 'YYYY-MM-DD HH:MM:SS +0000 UTC'
    if dt is None:
        try:
            dt = datetime.strptime(text, "%Y-%m-%d %H:%M:%S %z %Z")
        except ValueError:
            dt = None

    # Additional fallback stripping timezone information
    if dt is None:
        for layout in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
            try:
                # Ensure text is long enough before slicing
                if len(text) >= 19:
                    dt = datetime.strptime(text[:19], layout)
                    break
            except ValueError:
                continue

    if dt is None:
        return text

    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)

    return dt.strftime("%Y-%m-%d %H:%M:%S")


def build_mode_indicators(name, persist=False):
    """Return concatenated mode indicators (VM, tmp, persist)."""
    indicators = []
    if name.startswith("fdevc.vm."):
        indicators.append(f" {COLOR_MAGENTA}🖥️ VM mode{COLOR_RESET}")
    if name.endswith(".tmp"):
        indicators.append(f" {COLOR_ORANGE}🕒 ephemeral{COLOR_RESET}")
    if persist:
        indicators.append(f" {COLOR_PINK}♾  persist{COLOR_RESET}")
    return "".join(indicators)


NAME_MIN_WIDTH = 28
MAX_FIELD_WIDTH = 80  # Maximum width for project path and command fields
HEADER_EXTRA_PADDING = 2
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_IMAGE_PATH = os.environ.get("FDEVC_IMAGE") or os.path.join(
    SCRIPT_DIR, "Dockerfile"
)
DEFAULT_IMAGE_ABS = os.path.abspath(DEFAULT_IMAGE_PATH)

ADJECTIVES = [
    "happy",
    "calm",
    "bold",
    "eager",
    "gentle",
    "bright",
    "mellow",
    "serene",
    "joyful",
    "brave",
    "curious",
    "lively",
    "proud",
    "spirited",
    "tranquil",
    "radiant",
    "clever",
    "swift",
    "nimble",
    "fearless",
    "daring",
    "playful",
    "sunny",
    "cozy",
    "sparkling",
    "valiant",
    "whimsical",
    "zen",
    "dapper",
    "vivid",
    "cosmic",
    "stellar",
]

ANIMALS = [
    "fox",
    "panda",
    "otter",
    "lynx",
    "heron",
    "dolphin",
    "sparrow",
    "wolf",
    "koala",
    "tiger",
    "alpaca",
    "falcon",
    "rabbit",
    "bison",
    "jaguar",
    "whale",
    "phoenix",
    "orca",
    "badger",
    "lemur",
    "beaver",
    "owl",
    "eagle",
    "seal",
    "puma",
    "ibis",
    "yak",
    "wren",
    "penguin",
    "hedgehog",
    "narwhal",
    "raven",
    "mongoose",
]


def generate_project_label():
    """Generate a random project label (adjective-animal)."""
    adj = random.choice(ADJECTIVES)
    animal = random.choice(ANIMALS)
    return f"{adj}-{animal}"


def format_image_display(image_val, project_path):
    """Format image value for display, handling relative paths and defaults."""
    if not image_val:
        return f"{COLOR_CYAN}🐳 default{COLOR_RESET}"

    image_abs = os.path.abspath(image_val) if os.path.isabs(image_val) else None

    # Try to display relative to project path if both are absolute
    if project_path and os.path.isabs(project_path):
        project_abs = os.path.abspath(project_path)
        target_abs = image_abs or os.path.abspath(os.path.join(project_abs, image_val))
        try:
            common_root = os.path.commonpath([project_abs, target_abs])
        except ValueError:
            common_root = None
        if common_root == project_abs:
            rel_part = os.path.relpath(target_abs, project_abs)
            return f"{COLOR_CYAN}🐳 ./{rel_part}{COLOR_RESET}"

    # Check if it's the default image
    image_abs = image_abs or os.path.abspath(image_val)
    if image_abs == DEFAULT_IMAGE_ABS:
        return f"{COLOR_CYAN}🐳 default{COLOR_RESET}"

    return f"{COLOR_CYAN}🐳 {image_val}{COLOR_RESET}"


def format_socket_display(socket_raw):
    """Format socket configuration for display."""
    if isinstance(socket_raw, str):
        socket_enabled = socket_raw.strip().lower() in {"true", "1", "yes"}
    else:
        socket_enabled = bool(socket_raw)

    socket_symbol = "✓" if socket_enabled else "✗"
    socket_color = COLOR_GREEN if socket_enabled else COLOR_RED
    return f"{socket_color}{socket_symbol} socket{COLOR_RESET}"


def truncate_field(text, max_width=MAX_FIELD_WIDTH):
    """Truncate text if it exceeds max_width, adding ellipsis."""
    if not text:
        return ""
    if len(text) <= max_width:
        return text
    return text[: max_width - 3] + "..."


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
    created_at="",
    persist="",
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
    if project_path:
        cfg["project_path"] = project_path
    else:
        cfg.pop("project_path", None)
    if startup_cmd:
        cfg["startup_cmd"] = startup_cmd
    else:
        cfg.pop("startup_cmd", None)
    # Remove legacy project_alias if it exists
    cfg.pop("project_alias", None)

    if socket_state is not None:
        socket_value = str(socket_state).strip().lower()
        if socket_value in {"true", "false"}:
            cfg["socket"] = socket_value == "true"
        else:
            cfg.pop("socket", None)

    if created_at:
        cfg["created_at"] = created_at
    else:
        if not cfg.get("created_at"):
            cfg["created_at"] = (
                datetime.now(timezone.utc)
                .replace(microsecond=0)
                .isoformat()
                .replace("+00:00", "Z")
            )

    # Set persist based on the passed value
    persist_str = str(persist).strip().lower() if persist else ""
    cfg["persist"] = persist_str in ("true", "1", "yes", "on")

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
    docker_containers = {}
    for line in sys.stdin:
        if line.strip():
            parts = line.strip().split("|||")
            if len(parts) >= 2:
                name, status = parts[0], parts[1]
                mounts = parts[3] if len(parts) >= 4 else ""
                socket_label = parts[4] if len(parts) >= 5 else ""
                created_at = parts[5] if len(parts) >= 6 else ""
                docker_containers[name] = {
                    "status": status,
                    "mounts": mounts,
                    "socket_label": socket_label,
                    "created_at": created_at,
                }

    config_data = {}
    if config_file and os.path.exists(config_file):
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                config_data = json.load(f)
        except (json.JSONDecodeError, OSError):
            pass

    all_containers = {}
    for name, info in docker_containers.items():
        all_containers[name] = {
            "status": info.get("status"),
            "mounts": info.get("mounts", ""),
            "socket_label": info.get("socket_label", ""),
            "created_at": info.get("created_at", ""),
            "in_docker": True,
        }
    for name in config_data:
        if name not in all_containers:
            all_containers[name] = {
                "status": None,
                "in_docker": False,
                "created_at": "",
            }

    if not all_containers:
        print("No dev containers found.")
        sys.exit(0)

    rows = []
    for idx, name in enumerate(sorted(all_containers.keys()), 1):
        container_info = all_containers[name]
        cfg = config_data.get(name, {})

        if container_info["in_docker"]:
            status = container_info["status"] or ""
            if "Up" in status:
                status_display = "Running ●"
            else:
                status_display = "Stopped ○"
        else:
            status_display = "Saved ◌"

        config_lines = []

        docker_cmd_display = cfg.get("docker_cmd") or os.environ.get(
            "FDEVC_DOCKER", "docker"
        )

        socket_raw = cfg.get("socket")
        if socket_raw is None:
            socket_label = (container_info.get("socket_label") or "").strip().lower()
            if socket_label in {"true", "1", "yes"}:
                socket_enabled = True
            elif socket_label in {"false", "0", "no"}:
                socket_enabled = False
            else:
                mounts = (container_info.get("mounts") or "").lower()
                socket_enabled = "/var/run/docker.sock" in mounts
        elif isinstance(socket_raw, str):
            lowered = socket_raw.strip().lower()
            if lowered in {"false", "0", "no"}:
                socket_enabled = False
            elif lowered in {"true", "1", "yes"}:
                socket_enabled = True
            else:
                socket_enabled = False
        else:
            socket_enabled = bool(socket_raw)

        socket_segment = format_socket_display(socket_enabled)

        config_lines.append(
            f"{COLOR_CYAN}💻 {docker_cmd_display}{COLOR_RESET} {socket_segment}{build_mode_indicators(name, cfg.get('persist'))}"
        )

        project_path = cfg.get("project_path")
        display_project_path = (
            collapse_home_path(project_path) if project_path else None
        )
        truncated_project = (
            truncate_field(display_project_path) if display_project_path else None
        )

        image_val = cfg.get("image")
        image_line = format_image_display(image_val, project_path)
        if image_line and (not config_lines or config_lines[-1] != image_line):
            config_lines.append(image_line)

        if truncated_project:
            config_lines.append(f"{COLOR_YELLOW}📁 {truncated_project}{COLOR_RESET}")

        ports_val = cfg.get("ports")
        if ports_val:
            if isinstance(ports_val, list):
                ports_str = " ".join(str(p) for p in ports_val)
            else:
                ports_str = str(ports_val)
            if ports_str:
                config_lines.append(f"{COLOR_BLUE}🔀 {ports_str}{COLOR_RESET}")

        if cfg.get("startup_cmd"):
            truncated_cmd = truncate_field(cfg["startup_cmd"])
            config_lines.append(f"{COLOR_YELLOW}▶ {truncated_cmd}{COLOR_RESET}")

        created_display = ""
        raw_created = ""
        if container_info.get("created_at"):
            raw_created = container_info["created_at"].strip()
        elif cfg.get("created_at"):
            raw_created = str(cfg["created_at"]).strip()

        created_display = format_created_timestamp(raw_created)

        rows.append((str(idx), name, created_display, status_display, config_lines))

    idx_width = max(len("#"), max(len(row[0]) for row in rows))
    name_width = max(
        NAME_MIN_WIDTH, len("FAST DEV CONTAINERS"), max(len(row[1]) for row in rows)
    )
    created_width = max(len("CREATED"), max(len(row[2]) for row in rows))
    status_width = max(len("STATUS"), max(len(row[3]) for row in rows))

    header_prefix = f"{'#':<{idx_width}}  {'FAST DEV CONTAINERS':<{name_width}}  "
    header_created = "CREATED".rjust(created_width)
    header_status = "STATUS".rjust(status_width)
    header_text = header_prefix + header_created + "  " + header_status

    table_width = visible_length(header_text)
    rendered_rows = []

    for row in rows:
        idx, name, created_display, status, config_lines = row

        if "●" in status:
            status_color = COLOR_GREEN
        elif "○" in status:
            status_color = COLOR_RED
        else:
            status_color = COLOR_DIM

        status_plain = status.strip().rjust(status_width)
        status_colored = f"{status_color}{status_plain}{COLOR_RESET}"

        name_colored = f"{COLOR_BOLD}{name.ljust(name_width)}{COLOR_RESET}"
        created_plain = created_display.strip().rjust(created_width)
        created_colored = f"{COLOR_DIM}{created_plain}{COLOR_RESET}"
        prefix = f"{idx:<{idx_width}}  {name_colored}  {created_colored}  "
        table_width = max(
            table_width,
            visible_length(prefix) + visible_length(status_plain),
        )

        rendered_config = []
        for line in config_lines:
            config_line = f"    {line}"
            table_width = max(table_width, visible_length(config_line))
            rendered_config.append(config_line)

        rendered_rows.append((prefix, status_colored, rendered_config))

    table_width = max(table_width, visible_length(header_text)) + HEADER_EXTRA_PADDING

    # Print header aligned to table width
    header_spacing = max(
        0,
        table_width
        - visible_length(header_prefix)
        - visible_length(header_created)
        - 2
        - visible_length(header_status),
    )
    header_line = header_prefix + header_created + " " * header_spacing + header_status
    header_line = pad_to_width(header_line, table_width)
    print(f"{COLOR_BOLD}{COLOR_CYAN}{header_line}{COLOR_RESET}")
    print(f"{COLOR_DIM}{'─' * table_width}{COLOR_RESET}")

    for prefix, status_colored, config_lines in rendered_rows:
        spacing = max(
            0, table_width - visible_length(prefix) - visible_length(status_colored)
        )
        main_line = prefix + " " * spacing + status_colored
        print(pad_to_width(main_line, table_width))
        for line in config_lines:
            print(pad_to_width(line, table_width))


def resolve_index(config_file, index_str):
    """Resolve a container id against docker and config entries."""
    try:
        index_num = int(index_str)
        if index_num <= 0:
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

    if 1 <= index_num <= len(combined_names):
        print(combined_names[index_num - 1])
    else:
        print("")


def list_configs(config_file):
    """Display all saved configurations in a table (reuses list_containers logic)."""
    if not os.path.exists(config_file):
        print(f"{COLOR_DIM}No configurations saved{COLOR_RESET}")
        return

    try:
        with open(config_file, "r", encoding="utf-8") as f:
            config_data = json.load(f)
    except (json.JSONDecodeError, IOError):
        print(f"{COLOR_RED}✗ Failed to read config file{COLOR_RESET}", file=sys.stderr)
        return

    if not config_data:
        print(f"{COLOR_DIM}No configurations saved{COLOR_RESET}")
        return

    # Build rows using the same logic as list_containers, but without status
    rows = []
    for idx, name in enumerate(sorted(config_data.keys()), 1):
        cfg = config_data[name]

        config_lines = []

        docker_cmd_display = cfg.get("docker_cmd") or os.environ.get(
            "FDEVC_DOCKER", "docker"
        )
        socket_segment = format_socket_display(cfg.get("socket"))

        config_lines.append(
            f"{COLOR_CYAN}💻 {docker_cmd_display}{COLOR_RESET} {socket_segment}{build_mode_indicators(name, cfg.get('persist'))}"
        )

        project_path = cfg.get("project_path")
        display_project_path = (
            collapse_home_path(project_path) if project_path else None
        )
        truncated_project = (
            truncate_field(display_project_path) if display_project_path else None
        )

        image_val = cfg.get("image")
        image_line = format_image_display(image_val, project_path)
        if image_line:
            config_lines.append(image_line)

        if truncated_project:
            config_lines.append(f"{COLOR_YELLOW}📁 {truncated_project}{COLOR_RESET}")

        ports_val = cfg.get("ports")
        if ports_val:
            if isinstance(ports_val, list):
                ports_str = " ".join(str(p) for p in ports_val)
            else:
                ports_str = str(ports_val)
            if ports_str:
                config_lines.append(f"{COLOR_BLUE}🔀 {ports_str}{COLOR_RESET}")

        if cfg.get("startup_cmd"):
            truncated_cmd = truncate_field(cfg["startup_cmd"])
            config_lines.append(f"{COLOR_YELLOW}▶ {truncated_cmd}{COLOR_RESET}")

        raw_created = str(cfg.get("created_at", "")).strip()
        created_display = format_created_timestamp(raw_created)

        rows.append((str(idx), name, created_display, config_lines))

    # Calculate widths
    idx_width = max(len("#"), max(len(row[0]) for row in rows))
    name_width = max(
        NAME_MIN_WIDTH, len("SAVED CONFIGURATIONS"), max(len(row[1]) for row in rows)
    )
    created_width = max(len("CREATED"), max(len(row[2]) for row in rows))

    header_prefix = f"{'#':<{idx_width}}  {'SAVED CONFIGURATIONS':<{name_width}}  "
    header_created = "CREATED".rjust(created_width)
    header_text = header_prefix + header_created

    table_width = visible_length(header_text)
    rendered_rows = []

    for row in rows:
        idx, name, created_display, config_lines = row

        name_colored = f"{COLOR_BOLD}{name.ljust(name_width)}{COLOR_RESET}"
        created_plain = created_display.strip().rjust(created_width)
        created_colored = f"{COLOR_DIM}{created_plain}{COLOR_RESET}"

        rendered_config = []
        for line in config_lines:
            config_line = f"    {line}"
            table_width = max(table_width, visible_length(config_line))
            rendered_config.append(config_line)

        rendered_rows.append((idx, name_colored, created_colored, rendered_config))

    table_width = max(table_width, visible_length(header_text)) + HEADER_EXTRA_PADDING

    # Print header with proper spacing
    header_spacing = max(
        0, table_width - visible_length(header_prefix) - visible_length(header_created)
    )
    header_line = header_prefix + " " * header_spacing + header_created
    header_line = pad_to_width(header_line, table_width)
    print(f"{COLOR_BOLD}{COLOR_CYAN}{header_line}{COLOR_RESET}")
    print(f"{COLOR_DIM}{'─' * table_width}{COLOR_RESET}")

    # Print rows with proper spacing
    for idx, name_colored, created_colored, rendered_config in rendered_rows:
        # Build row with spacing to align created column to the right
        row_prefix = f"{idx:<{idx_width}}  {name_colored}  "
        row_spacing = max(
            0,
            table_width - visible_length(row_prefix) - visible_length(created_colored),
        )
        row_line = row_prefix + " " * row_spacing + created_colored
        print(row_line)
        for config_line in rendered_config:
            print(config_line)


def remove_all_configs(config_file):
    """Remove all configurations."""
    if os.path.exists(config_file):
        try:
            os.remove(config_file)
            print(f"{COLOR_GREEN}✓ All configurations removed{COLOR_RESET}")
        except IOError as e:
            print(
                f"{COLOR_RED}✗ Failed to remove config file: {e}{COLOR_RESET}",
                file=sys.stderr,
            )
            sys.exit(1)
    else:
        print(f"{COLOR_YELLOW}⚠ No config file found{COLOR_RESET}")


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
            sys.argv[10] if len(sys.argv) > 10 else "",
            sys.argv[11] if len(sys.argv) > 11 else "",
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
    elif command == "random_label":
        print(generate_project_label())
    elif command == "list_configs":
        list_configs(sys.argv[2])
    elif command == "remove_all_configs":
        remove_all_configs(sys.argv[2])
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
