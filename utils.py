#!/usr/bin/env python3

import json
import os
import random
import re
import sys
from datetime import datetime, timezone
from typing import Any

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
TIMESTAMP_FRACTION_RE = re.compile(r"(\.\d+)(?=(?:Z|[+-]\d{2}:?\d{2})?$)")


def visible_length(text: str) -> int:
    """Return the printable length of text without ANSI escape codes."""
    return len(ANSI_ESCAPE_RE.sub("", text))


def pad_to_width(text: str, target_width: int, align_right: bool = False) -> str:
    """Pad a text (with ANSI codes) to the target visible width."""
    extra = target_width - visible_length(text)
    if extra > 0:
        if align_right:
            return f"{' ' * extra}{text}"
        else:
            return f"{text}{' ' * extra}"
    return text


def align_colored_text(
    text: str, color: str, width: int, align_right: bool = False
) -> str:
    """Apply color to text and align it properly within the given width."""
    colored_text = f"{color}{text}{COLOR_RESET}"
    return pad_to_width(colored_text, width, align_right=align_right)


def collapse_home_path(path: str) -> str:
    """Replace a leading HOME directory with ~ for display."""
    if not path:
        return path
    try:
        home_norm = os.path.normpath(os.path.expanduser("~"))
        absolute_norm = os.path.normpath(os.path.abspath(os.path.expanduser(path)))
    except (TypeError, ValueError, OSError):
        return path
    if absolute_norm == home_norm:
        return "~"
    prefix = home_norm + os.sep
    if absolute_norm.startswith(prefix):
        return "~" + absolute_norm[len(home_norm) :]
    return path


def format_created_timestamp(raw: str) -> str:
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
    if dt is None and len(text) >= 19:
        for layout in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
            try:
                dt = datetime.strptime(text[:19], layout)
                break
            except ValueError:
                continue

    if dt is None:
        return text

    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)

    return dt.strftime("%Y-%m-%d %H:%M")


def normalize_iso_timestamp(value: Any) -> str:
    """Trim sub-second precision from ISO-like timestamps."""
    if value is None:
        return ""

    text = str(value).strip()
    if not text:
        return ""

    return TIMESTAMP_FRACTION_RE.sub("", text, count=1)


def build_mode_indicators(name: str, persist: bool = False) -> str:
    """Return concatenated mode indicators (VM, tmp, persist)."""
    indicators: list[str] = []
    if name.startswith("fdevc.vm."):
        indicators.append(f" {COLOR_MAGENTA}🖥️ VM mode{COLOR_RESET}")
    if name.endswith(".tmp"):
        indicators.append(f" {COLOR_ORANGE}🕒 ephemeral{COLOR_RESET}")
    if persist:
        indicators.append(f" {COLOR_PINK}♾  persist{COLOR_RESET}")
    return "".join(indicators)


NAME_MIN_WIDTH = 28
HEADER_EXTRA_PADDING = 2
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_IMAGE_PATH = os.environ.get("FDEVC_IMAGE", "philogicae/fdevc:latest")


def _is_docker_image_name(path: str) -> bool:
    """Check if a path is a Docker image name (registry/name:tag) vs a file path."""
    if path.endswith(".Dockerfile") or path.endswith("/Dockerfile"):
        return False
    if ":" in path and not path.startswith("/") and not path.startswith("./"):
        return True
    if path.startswith("./") or path.startswith("/"):
        return False
    if "/" in path and "." not in os.path.basename(path):
        return True
    return False


DEFAULT_IMAGE_ABS = (
    os.path.abspath(DEFAULT_IMAGE_PATH)
    if DEFAULT_IMAGE_PATH
    and not _is_docker_image_name(DEFAULT_IMAGE_PATH)
    and os.path.exists(DEFAULT_IMAGE_PATH)
    else DEFAULT_IMAGE_PATH
)

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


def generate_project_label() -> str:
    """Generate a random project label (adjective-animal)."""
    adj = random.choice(ADJECTIVES)
    animal = random.choice(ANIMALS)
    return f"{adj}-{animal}"


def format_image_display(image_val: str, project_path: str | None) -> str:
    """Format image value for display, handling relative paths and defaults."""
    if not image_val:
        return f"{COLOR_CYAN}🐳 default image{COLOR_RESET}"

    # Check if it's the default image first (compare both as-is and normalized)
    if image_val == DEFAULT_IMAGE_PATH or image_val == DEFAULT_IMAGE_ABS:
        return f"{COLOR_CYAN}🐳 default image{COLOR_RESET}"

    # If it's a Docker image name (not a file path), display as-is
    if _is_docker_image_name(image_val):
        return f"{COLOR_CYAN}🐳 {image_val}{COLOR_RESET}"

    # Handle file paths
    image_abs = (
        os.path.abspath(image_val) if not os.path.isabs(image_val) else image_val
    )

    # Try to display relative to project path if both are absolute
    if project_path and os.path.isabs(project_path):
        project_abs = os.path.abspath(project_path)
        try:
            common_root = os.path.commonpath([project_abs, image_abs])
            if common_root == project_abs:
                rel_part = os.path.relpath(image_abs, project_abs)
                return f"{COLOR_CYAN}🐳 ./{rel_part}{COLOR_RESET}"
        except ValueError:
            pass

    # Check if the absolute path matches default
    if image_abs == DEFAULT_IMAGE_ABS:
        return f"{COLOR_CYAN}🐳 default image{COLOR_RESET}"

    return f"{COLOR_CYAN}🐳 {image_val}{COLOR_RESET}"


def format_socket_display(socket_raw: Any) -> str:
    """Format socket configuration for display."""
    if isinstance(socket_raw, str):
        socket_enabled = socket_raw.strip().lower() in {"true", "1", "yes"}
    else:
        socket_enabled = bool(socket_raw)

    socket_symbol = "✓" if socket_enabled else "✗"
    socket_color = COLOR_GREEN if socket_enabled else COLOR_RED
    return f"{socket_color}{socket_symbol} socket{COLOR_RESET}"


def prettify_placeholder_path(path: str, project_path: str | None = None) -> str:
    """Convert placeholder paths (__HOME__, __PROJECT_PATH__) to display format (~, .)."""
    if not path:
        return path
    if path == "__PROJECT_PATH__":
        return "."
    elif path == "__HOME__":
        return "~"
    elif path.startswith("__PROJECT_PATH__/"):
        return "./" + path[17:]
    elif path.startswith("__HOME__/"):
        return "~/" + path[9:]
    else:
        display = collapse_home_path(path)
        if project_path and os.path.isabs(project_path) and os.path.isabs(display):
            try:
                project_norm = os.path.normpath(project_path)
                display_norm = os.path.normpath(display)
                if display_norm == project_norm:
                    display = "."
                elif display_norm.startswith(project_norm + os.sep):
                    rel_path = os.path.relpath(display_norm, project_norm)
                    display = "./" + rel_path
            except (ValueError, OSError):
                pass
        return display


def format_ports_display(ports_val: Any) -> str:
    """Format ports for display, replacing ':' with '->'."""
    if not ports_val:
        return ""
    if isinstance(ports_val, list):
        ports_str = "\n    ".join(f"{COLOR_BLUE}🔀 {p}{COLOR_RESET}" for p in ports_val)
    else:
        ports_str = f"{COLOR_BLUE}🔀 {ports_val}{COLOR_RESET}"
    return ports_str.replace(":", f"{COLOR_RESET} -> {COLOR_BLUE}")


def format_volume_display(
    volume: str,
    project_path: str | None,
    container_name: str | None = None,
    dim: bool = False,
) -> str:
    """Format a single volume mount for display with different colors by volume type."""
    if not volume:
        return volume

    # Use dim colors if requested
    source_bright_color = COLOR_YELLOW
    source_named_color = COLOR_CYAN
    dest_color = COLOR_PINK
    excluded_color = COLOR_RED

    if dim:
        source_bright_color = COLOR_DIM
        source_named_color = COLOR_DIM
        dest_color = COLOR_DIM
        excluded_color = COLOR_DIM

    if ":" not in volume:
        source = volume
        if container_name and source.startswith(f"{container_name}."):
            source = source[len(container_name) + 1 :]
        return f"⛔ {COLOR_RESET}-> {excluded_color}{prettify_placeholder_path(source, project_path)}{COLOR_RESET}"

    parts = volume.split(":", 1)
    source = parts[0]
    dest = parts[1] if len(parts) > 1 else ""
    if container_name and source.startswith(f"{container_name}."):
        source = source[len(container_name) + 1 :]
    source_display = prettify_placeholder_path(source, project_path)

    if (
        source_display.startswith("/")
        or source_display.startswith(".")
        or source_display.startswith("~")
    ):
        source_color = source_bright_color
    else:
        source_color = source_named_color
    return f"{source_color}{source_display}{COLOR_RESET} -> {dest_color}{dest}{COLOR_RESET}"


def load_config(config_file: str, container_name: str) -> None:
    """Load configuration for a specific container."""
    try:
        with open(config_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        cfg = data.get(container_name, {})
        print(json.dumps(cfg))
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        print("{}")


def get_config_value(key: str, default: str = "") -> None:
    """Extract a value from JSON config passed via stdin."""
    try:
        cfg = json.load(sys.stdin)
        val = cfg.get(key, default)
        if isinstance(val, list):
            # Use ||| separator for volumes, space for others (ports)
            if key == "volumes":
                print("|||".join(val))
            else:
                print(" ".join(val))
        else:
            print(val)
    except (json.JSONDecodeError, KeyError, AttributeError):
        print(default)


def save_config(
    config_file: str,
    container_name: str,
    ports: str = "",
    image: str = "",
    docker_cmd: str = "",
    project_path: str = "",
    startup_cmd: str = "",
    socket_state: Any = None,
    created_at: str = "",
    persist: str = "",
    volumes: str = "",
) -> None:
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
    if volumes:
        cfg["volumes"] = [v for v in volumes.split("|||") if v]
    else:
        cfg.pop("volumes", None)
    cfg.pop("project_alias", None)

    if socket_state is not None:
        socket_value = str(socket_state).strip().lower()
        if socket_value in {"true", "false"}:
            cfg["socket"] = socket_value == "true"
        else:
            cfg.pop("socket", None)

    created_at = normalize_iso_timestamp(created_at)

    if created_at:
        cfg["created_at"] = created_at
    else:
        if not cfg.get("created_at"):
            cfg["created_at"] = normalize_iso_timestamp(
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


def remove_config(config_file: str, container_name: str) -> None:
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


def list_containers(config_file: str) -> None:
    """List all containers with their status and configuration."""
    docker_containers = {}
    for line in sys.stdin:
        if line.strip():
            parts = line.strip().split("|||")
            if len(parts) >= 2:
                name, status = parts[0], parts[1]
                mounts_json = parts[3] if len(parts) >= 4 else ""
                socket_label = parts[4] if len(parts) >= 5 else ""
                created_at = parts[5] if len(parts) >= 6 else ""

                # Parse JSON mounts to extract volume information
                parsed_mounts = []
                if mounts_json and mounts_json not in ("", "null", "[]"):
                    try:
                        mounts_data = json.loads(mounts_json)
                        if isinstance(mounts_data, list):
                            for mount in mounts_data:
                                if isinstance(mount, dict):
                                    mount_type = mount.get("Type", "")
                                    destination = mount.get("Destination", "")
                                    # For named volumes, use Name instead of Source
                                    if mount_type == "volume":
                                        source = mount.get("Name", "")
                                    else:
                                        source = mount.get("Source", "")
                                    if source and destination:
                                        parsed_mounts.append(f"{source}:{destination}")
                                    elif source:
                                        parsed_mounts.append(source)
                    except (json.JSONDecodeError, AttributeError, TypeError):
                        # Fallback to old format (comma-separated string)
                        if "," in mounts_json:
                            parsed_mounts = [
                                m.strip() for m in mounts_json.split(",") if m.strip()
                            ]
                        elif mounts_json:
                            parsed_mounts = [mounts_json]

                docker_containers[name] = {
                    "status": status,
                    "mounts": parsed_mounts,
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
            "mounts": info.get("mounts", []),
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
        print("No dev containers found")
        sys.exit(0)

    rows = []
    for idx, name in enumerate(sorted(all_containers.keys()), 1):
        container_info = all_containers[name]
        cfg = config_data.get(name, {})

        if container_info["in_docker"]:
            status = container_info["status"] or ""
            status_str = str(status)
            if "Up" in status_str:
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
            socket_label_raw = container_info.get("socket_label") or ""
            socket_label = str(socket_label_raw).strip().lower()
            if socket_label in {"true", "1", "yes"}:
                socket_enabled = True
            elif socket_label in {"false", "0", "no"}:
                socket_enabled = False
            else:
                mounts_from_docker = container_info.get("mounts") or []
                if isinstance(mounts_from_docker, list):
                    socket_enabled = any(
                        "/var/run/docker.sock" in str(m).lower()
                        for m in mounts_from_docker
                    )
                else:
                    socket_enabled = (
                        "/var/run/docker.sock" in str(mounts_from_docker).lower()
                    )
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
            prettify_placeholder_path(project_path) if project_path else None
        )

        image_val = cfg.get("image")
        image_line = format_image_display(image_val, project_path)
        if image_line and (not config_lines or config_lines[-1] != image_line):
            config_lines.append(image_line)

        if display_project_path:
            config_lines.append(f"{COLOR_YELLOW}📁 {display_project_path}{COLOR_RESET}")

        ports_val = cfg.get("ports")
        ports_display = format_ports_display(ports_val)
        if ports_display:
            config_lines.append(ports_display)

        # Get volumes from config or Docker mounts
        volumes_val = cfg.get("volumes")
        volume_list = []

        # Use config volumes if available and non-empty
        if volumes_val and (
            (isinstance(volumes_val, list) and len(volumes_val) > 0)
            or (not isinstance(volumes_val, list))
        ):
            volume_list = (
                volumes_val if isinstance(volumes_val, list) else [volumes_val]
            )
        # Otherwise, use Docker mounts (for --tmp containers or containers without config)
        if not volume_list and container_info["in_docker"]:
            mounts_from_docker = container_info.get("mounts", [])
            if isinstance(mounts_from_docker, list):
                for mount in mounts_from_docker:
                    mount_str = str(mount).strip()
                    if mount_str and "docker.sock" not in mount_str:
                        volume_list.append(mount_str)
            elif mounts_from_docker:
                # Fallback for old string format
                for mount in str(mounts_from_docker).split(","):
                    mount = mount.strip()
                    if mount and "docker.sock" not in mount:
                        volume_list.append(mount)

        if volume_list:
            # Sort volumes: mount volumes (with :) first, then excluded volumes (without :)
            mount_volumes = [vol for vol in volume_list if ":" in str(vol)]
            excluded_volumes = [vol for vol in volume_list if ":" not in str(vol)]
            sorted_volumes = mount_volumes + excluded_volumes

            # Filter out excluded volumes from display and count them
            display_volumes = [vol for vol in sorted_volumes if ":" in str(vol)]
            excluded_count = len(excluded_volumes)

            for vol in display_volumes:
                vol_str = str(vol)
                if vol_str and not (
                    vol_str == "/var/run/docker.sock:/var/run/docker.sock"
                    or "docker.sock" in vol_str
                ):
                    formatted_vol = format_volume_display(vol_str, project_path, name)
                    if formatted_vol:
                        config_lines.append(f"💾 {formatted_vol}")

            # Show excluded count if there are any excluded volumes
            if excluded_count > 0:
                config_lines.append(
                    f"⛔ {COLOR_RED}excluded paths: {excluded_count}{COLOR_RESET}"
                )

        if cfg.get("startup_cmd"):
            display_cmd = prettify_placeholder_path(cfg["startup_cmd"], project_path)
            config_lines.append(f"{COLOR_ORANGE}⚙️ {display_cmd}{COLOR_RESET}")

        created_display = ""
        raw_created = ""
        created_at_raw = container_info.get("created_at")
        if created_at_raw:
            raw_created = str(created_at_raw).strip()
        elif cfg.get("created_at"):
            raw_created = str(cfg["created_at"]).strip()

        created_display = format_created_timestamp(raw_created)

        rows.append((str(idx), name, created_display, status_display, config_lines))

    idx_width = max(len("#"), max(len(row[0]) for row in rows))
    created_width = max(len("CREATED"), max(len(row[2]) for row in rows), 16)
    status_width = max(len("STATUS"), max(len(row[3]) for row in rows))

    max_name_width = max(len("FAST DEV CONTAINERS"), max(len(row[1]) for row in rows))
    max_config_width = 0
    for row in rows:
        for line in row[4]:
            max_config_width = max(max_config_width, visible_length(line))

    name_width = max(
        NAME_MIN_WIDTH,
        max_name_width,
        max_config_width - idx_width - created_width - status_width - 2,
    )

    table_width = idx_width + 2 + name_width + 2 + created_width + 2 + status_width

    header_idx = f"{'#':<{idx_width}}"
    header_name = f"{'FAST DEV CONTAINERS':<{name_width}}"
    header_created = f"{'CREATED':>{created_width}}"
    header_status = f"{'STATUS':>{status_width}}"
    header_text = f"{header_idx}  {header_name}  {header_created}  {header_status}"

    rendered_rows = []

    for row in rows:
        row_idx, row_name, row_created, row_status, row_config = row

        if "●" in row_status:
            status_color = COLOR_GREEN
        elif "○" in row_status:
            status_color = COLOR_RED
        else:
            status_color = COLOR_DIM

        idx_aligned = f"{row_idx:<{idx_width}}"
        name_aligned = f"{row_name:<{name_width}}"
        created_aligned = align_colored_text(
            row_created, COLOR_DIM, created_width, align_right=True
        )
        status_aligned = align_colored_text(
            row_status, status_color, status_width, align_right=True
        )

        idx_colored = f"{COLOR_DIM}{idx_aligned}{COLOR_RESET}"
        name_colored = f"{COLOR_BOLD}{name_aligned}{COLOR_RESET}"

        row_line = f"{idx_colored}  {name_colored}  {created_aligned}  {status_aligned}"

        rendered_config = []
        for line in row_config:
            config_line = f"    {line}"
            rendered_config.append(config_line)

        rendered_rows.append((row_line, rendered_config))

    print(f"{COLOR_BOLD}{COLOR_CYAN}{header_text}{COLOR_RESET}")
    print(f"{COLOR_DIM}{'─' * table_width}{COLOR_RESET}")

    for row_line, rendered_config in rendered_rows:
        print(row_line)
        for config_line in rendered_config:
            print(config_line)


def resolve_index(config_file: str, index_str: str) -> None:
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


def list_configs(config_file: str) -> None:
    """Display all saved configurations in a table (reuses list_containers logic)."""
    if not os.path.exists(config_file):
        config_dir = os.path.dirname(config_file)
        try:
            if config_dir:
                os.makedirs(config_dir, exist_ok=True)
            with open(config_file, "w", encoding="utf-8") as f:
                json.dump({}, f, indent=2, sort_keys=True)
        except OSError as exc:
            print(
                f"{COLOR_RED}✗ Failed to initialize config file ({exc}){COLOR_RESET}",
                file=sys.stderr,
            )
            return

    try:
        with open(config_file, "r", encoding="utf-8") as f:
            config_data = json.load(f)
    except (json.JSONDecodeError, IOError):
        print(f"{COLOR_RED}✗ Failed to read config file{COLOR_RESET}", file=sys.stderr)
        return

    if not config_data:
        print("No configurations saved")
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
            prettify_placeholder_path(project_path) if project_path else None
        )

        image_val = cfg.get("image")
        image_line = format_image_display(image_val, project_path)
        if image_line:
            config_lines.append(image_line)

        if display_project_path:
            config_lines.append(f"{COLOR_YELLOW}📁 {display_project_path}{COLOR_RESET}")

        ports_val = cfg.get("ports")
        ports_display = format_ports_display(ports_val)
        if ports_display:
            config_lines.append(ports_display)

        volumes_val = cfg.get("volumes")
        if volumes_val:
            volume_list = (
                volumes_val if isinstance(volumes_val, list) else [volumes_val]
            )
            # Sort volumes: mount volumes (with :) first, then excluded volumes (without :)
            mount_volumes = [vol for vol in volume_list if ":" in str(vol)]
            excluded_volumes = [vol for vol in volume_list if ":" not in str(vol)]
            sorted_volumes = mount_volumes + excluded_volumes

            for vol in sorted_volumes:
                vol_str = str(vol)
                if vol_str and not (
                    vol_str == "/var/run/docker.sock:/var/run/docker.sock"
                    or "docker.sock" in vol_str
                ):
                    formatted_vol = format_volume_display(vol_str, project_path, name)
                    if formatted_vol:
                        config_lines.append(f"💾 {formatted_vol}")

        if cfg.get("startup_cmd"):
            display_cmd = prettify_placeholder_path(cfg["startup_cmd"], project_path)
            config_lines.append(f"{COLOR_ORANGE}⚙️ {display_cmd}{COLOR_RESET}")

        raw_created = str(cfg.get("created_at", "")).strip()
        created_display = format_created_timestamp(raw_created)

        rows.append((str(idx), name, created_display, config_lines))

    config_header = collapse_home_path(config_file) if config_file else "CONFIGURATIONS"
    idx_width = max(len("#"), max(len(row[0]) for row in rows))
    created_width = max(len("CREATED"), max(len(row[2]) for row in rows), 16)

    max_name_width = max(len(config_header), max(len(row[1]) for row in rows))
    max_config_width = 0
    for row in rows:
        for line in row[3]:
            max_config_width = max(max_config_width, visible_length(line))

    name_width = max(
        NAME_MIN_WIDTH, max_name_width, max_config_width - idx_width - created_width - 4
    )

    table_width = idx_width + 2 + name_width + 2 + created_width

    header_idx = f"{'#':<{idx_width}}"
    header_name = f"{config_header:<{name_width}}"
    header_created = f"{'CREATED':>{created_width}}"
    header_text = f"{header_idx}  {header_name}  {header_created}"

    rendered_rows = []

    for row in rows:
        row_idx, row_name, row_created, row_config = row

        idx_aligned = f"{row_idx:<{idx_width}}"
        name_aligned = f"{row_name:<{name_width}}"
        created_aligned = align_colored_text(
            row_created, COLOR_DIM, created_width, align_right=True
        )

        idx_colored = f"{COLOR_DIM}{idx_aligned}{COLOR_RESET}"
        name_colored = f"{COLOR_BOLD}{name_aligned}{COLOR_RESET}"

        row_line = f"{idx_colored}  {name_colored}  {created_aligned}"

        rendered_config = []
        for line in row_config:
            config_line = f"    {line}"
            rendered_config.append(config_line)

        rendered_rows.append((row_line, rendered_config))

    print(f"{COLOR_BOLD}{COLOR_CYAN}{header_text}{COLOR_RESET}")
    print(f"{COLOR_DIM}{'─' * table_width}{COLOR_RESET}")

    for row_line, rendered_config in rendered_rows:
        print(row_line)
        for config_line in rendered_config:
            print(config_line)


def remove_all_configs(config_file: str) -> None:
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


def normalize_port(port: str) -> str:
    """Normalize port mapping to 'host:container' format."""
    if not port:
        return ""
    port = port.strip()
    if ":" in port:
        return port
    return f"{port}:{port}"


def normalize_ports_list(ports: str | list[str] | None) -> str:
    """Normalize ports to sorted space-separated string."""
    if not ports:
        return ""
    if isinstance(ports, str):
        ports_list = [p.strip() for p in ports.split() if p.strip()]
    else:
        ports_list = [str(p).strip() for p in ports if p]
    normalized = sorted(set(normalize_port(p) for p in ports_list if p))
    return " ".join(normalized)


def normalize_volumes_list(volumes: str | list[str] | None) -> str:
    """Normalize volumes to sorted ||| separated string."""
    if not volumes:
        return ""
    if isinstance(volumes, str):
        if "|||" in volumes:
            volumes_list = [v.strip() for v in volumes.split("|||") if v.strip()]
        else:
            volumes_list = [volumes.strip()] if volumes.strip() else []
    else:
        volumes_list = [str(v).strip() for v in volumes if v]

    # Filter out docker socket
    volumes_list = [
        v
        for v in volumes_list
        if v
        and v != "/var/run/docker.sock:/var/run/docker.sock"
        and "docker.sock" not in v
    ]

    # Sort: mount volumes first (with :), then excluded volumes (without :)
    mount_volumes = sorted(v for v in volumes_list if ":" in v)
    excluded_volumes = sorted(v for v in volumes_list if ":" not in v)

    all_volumes = mount_volumes + excluded_volumes
    return "|||".join(all_volumes) if all_volumes else ""


def normalize_volumes(
    volumes: str,
    container_name: str,
    project_path: str,
) -> None:
    """
    Normalize volumes for comparison by expanding paths and normalizing names.
    This replicates bash _normalize_volume_name and _collapse_volume logic.
    Prints the normalized volume string.
    """
    if not volumes:
        print("")
        return

    volume_list = [v.strip() for v in volumes.split("|||") if v.strip()]
    normalized_list = []

    for vol in volume_list:
        if not vol or vol == "/var/run/docker.sock:/var/run/docker.sock":
            continue

        # Expand __PROJECT_PATH__ and __HOME__ placeholders
        expanded_vol = vol
        if "__PROJECT_PATH__" in vol and project_path:
            expanded_vol = vol.replace("__PROJECT_PATH__", project_path)
        if "__HOME__" in vol:
            home = os.path.expanduser("~")
            expanded_vol = expanded_vol.replace("__HOME__", home)

        # Handle relative paths (./something)
        if ":" in expanded_vol:
            source, dest = expanded_vol.split(":", 1)
            if source.startswith("./"):
                if project_path:
                    source = project_path + source[1:]
                else:
                    source = os.getcwd() + source[1:]
            expanded_vol = f"{source}:{dest}"

        # Normalize volume names (add container prefix for named volumes)
        if ":" in expanded_vol:
            source, dest = expanded_vol.split(":", 1)
            # If source is not an absolute path and not relative, it's a named volume
            if not source.startswith("/") and not source.startswith("."):
                # Add container prefix if not already present
                if not source.startswith(f"{container_name}."):
                    source = f"{container_name}.{source}"
            expanded_vol = f"{source}:{dest}"
        else:
            # Excluded volume (no destination)
            if not expanded_vol.startswith("/") and not expanded_vol.startswith("."):
                if not expanded_vol.startswith(f"{container_name}."):
                    expanded_vol = f"{container_name}.{expanded_vol}"

        # Collapse back to placeholders for storage
        collapsed_vol = expanded_vol
        if project_path and collapsed_vol.startswith(project_path):
            collapsed_vol = collapsed_vol.replace(project_path, "__PROJECT_PATH__", 1)

        home = os.path.expanduser("~")
        if collapsed_vol.startswith(home):
            collapsed_vol = collapsed_vol.replace(home, "__HOME__", 1)

        normalized_list.append(collapsed_vol)

    # Sort: mount volumes first, then excluded volumes
    mount_volumes = sorted(v for v in normalized_list if ":" in v)
    excluded_volumes = sorted(v for v in normalized_list if ":" not in v)

    all_volumes = mount_volumes + excluded_volumes
    print("|||".join(all_volumes) if all_volumes else "")


def compare_configs(
    config_file: str,
    container_name: str,
    new_ports: str = "",
    new_image: str = "",
    new_docker_cmd: str = "",
    new_project_path: str = "",
    new_socket: str = "",
    new_volumes: str = "",
) -> None:
    """
    Compare saved config with new config and output differences.
    Prints JSON with 'differs' boolean, 'changes' array, and 'old_values' dict.
    """
    result: dict[str, Any] = {"differs": False, "changes": [], "old_values": {}}

    try:
        with open(config_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        saved_config = data.get(container_name, {})
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        # No saved config means it differs
        result["differs"] = True
        print(json.dumps(result))
        return

    if not saved_config:
        result["differs"] = True
        print(json.dumps(result))
        return

    # Get saved values
    saved_ports = saved_config.get("ports", "")
    saved_image = saved_config.get("image", "")
    saved_docker_cmd = saved_config.get("docker_cmd", "")
    saved_project_path = saved_config.get("project_path", "")
    saved_socket_raw = saved_config.get("socket")
    saved_volumes = saved_config.get("volumes", "")

    # Normalize socket values for comparison
    def normalize_socket(val: Any) -> str:
        if val is None:
            return ""
        if isinstance(val, bool):
            return "true" if val else "false"
        val_str = str(val).strip().lower()
        if val_str in ("true", "1", "yes"):
            return "true"
        if val_str in ("false", "0", "no"):
            return "false"
        return ""

    saved_socket = normalize_socket(saved_socket_raw)
    new_socket_norm = normalize_socket(new_socket)

    # Normalize and compare ports
    saved_ports_norm = normalize_ports_list(saved_ports)
    new_ports_norm = normalize_ports_list(new_ports)
    if saved_ports_norm != new_ports_norm:
        result["changes"].append("ports")
        result["old_values"]["ports"] = saved_ports_norm

    # Compare image
    if saved_image != new_image:
        result["changes"].append("image")
        result["old_values"]["image"] = saved_image

    # Compare docker_cmd
    if saved_docker_cmd != new_docker_cmd:
        result["changes"].append("docker")
        result["old_values"]["docker"] = saved_docker_cmd

    # Compare project_path
    if saved_project_path != new_project_path:
        result["changes"].append("project")
        result["old_values"]["project"] = saved_project_path

    # Compare socket
    if saved_socket != new_socket_norm:
        result["changes"].append("socket")
        result["old_values"]["socket"] = saved_socket

    # Normalize and compare volumes
    # Both should already be in collapsed form, but ensure consistent sorting
    saved_volumes_norm = normalize_volumes_list(saved_volumes)
    new_volumes_norm = normalize_volumes_list(new_volumes)

    # Debug: ensure both are truly normalized the same way
    if saved_volumes_norm != new_volumes_norm:
        result["changes"].append("volumes")
        result["old_values"]["volumes"] = saved_volumes_norm

    result["differs"] = len(result["changes"]) > 0
    print(json.dumps(result))


def _normalize_port_set(ports: str | list[str] | None) -> set[str]:
    if not ports:
        return set()
    if isinstance(ports, str):
        port_items = [p.strip() for p in ports.split() if p.strip()]
    else:
        port_items = [str(p).strip() for p in ports if p]
    normalized = {normalize_port(p) for p in port_items if p}
    return normalized


def _render_port_line(port: str, prefix: str, color: str) -> str:
    host, container = port.split(":", 1)
    prefix_text = f"{color}{prefix}{COLOR_RESET} " if prefix else ""
    line_color = color if prefix else COLOR_DIM
    arrow_color = COLOR_DIM if line_color == COLOR_DIM else line_color
    return (
        f"{prefix_text}{line_color}🔀 {host}{COLOR_RESET}"
        f" {arrow_color}→ {line_color}{container}{COLOR_RESET}"
    )


def _split_volumes(volumes_str: str) -> list[str]:
    if not volumes_str:
        return []
    return [v.strip() for v in volumes_str.split("|||") if v.strip()]


def format_config_display(
    ports: str = "",
    image: str = "",
    docker_cmd: str = "",
    project_path: str = "",
    socket_state: str = "",
    volumes: str = "",
    changes: str = "",
    old_values_json: str = "",
    container_name: str | None = None,
) -> None:
    """
    Format and display configuration at container launch.
    Changes is a comma-separated list of changed fields.
    old_values_json is a JSON string with old values for changed fields.
    """
    changed_fields = set(changes.split(",")) if changes else set()
    old_values = {}
    if old_values_json:
        try:
            old_values = json.loads(old_values_json)
        except (json.JSONDecodeError, TypeError):
            pass

    lines = []

    # Docker command and socket
    docker_display = (
        docker_cmd if docker_cmd else os.environ.get("FDEVC_DOCKER", "docker")
    )
    socket_display = format_socket_display(socket_state)

    if "docker" in changed_fields or "socket" in changed_fields:
        # Show diff for docker or socket
        if "docker" in changed_fields:
            old_docker = old_values.get("docker", "")
            lines.append(f"{COLOR_RED}- 💻 {old_docker}{COLOR_RESET}")
            lines.append(
                f"{COLOR_GREEN}+ 💻 {docker_display}{COLOR_RESET} {socket_display}"
            )
        elif "socket" in changed_fields:
            old_socket = old_values.get("socket", "")
            old_socket_display = format_socket_display(old_socket)
            lines.append(
                f"{COLOR_RED}- 💻 {docker_display}{COLOR_RESET} {old_socket_display}"
            )
            lines.append(
                f"{COLOR_GREEN}+ 💻 {docker_display}{COLOR_RESET} {socket_display}"
            )
    else:
        line = f"{COLOR_DIM}💻 {docker_display} {socket_display}{COLOR_RESET}"
        lines.append(line)

    # Image
    if image:
        image_line = format_image_display(image, project_path)
        if "image" in changed_fields:
            old_image = old_values.get("image", "")
            old_image_line = format_image_display(old_image, project_path)
            lines.append(f"{COLOR_RED}- {old_image_line}{COLOR_RESET}")
            lines.append(f"{COLOR_GREEN}+ {image_line}{COLOR_RESET}")
        else:
            # Make non-diff image line dim
            lines.append(f"{COLOR_DIM}{image_line}{COLOR_RESET}")

    # Project path
    if project_path or "project" in changed_fields:
        display_path = prettify_placeholder_path(project_path) if project_path else ""
        if "project" in changed_fields:
            old_project = old_values.get("project", "")
            old_display_path = (
                prettify_placeholder_path(old_project) if old_project else "(none)"
            )
            new_display_path = display_path if display_path else "(none)"
            lines.append(f"{COLOR_RED}- 📁 {old_display_path}{COLOR_RESET}")
            lines.append(f"{COLOR_GREEN}+ 📁 {new_display_path}{COLOR_RESET}")
        elif project_path:
            lines.append(f"{COLOR_DIM}📁 {display_path}{COLOR_RESET}")

    # Ports
    if ports or "ports" in changed_fields:
        new_ports_set = _normalize_port_set(ports)
        if "ports" in changed_fields:
            old_ports_set = _normalize_port_set(old_values.get("ports", ""))
            removed_ports = sorted(old_ports_set - new_ports_set)
            added_ports = sorted(new_ports_set - old_ports_set)
            unchanged_ports = sorted(old_ports_set & new_ports_set)

            if removed_ports:
                for port in removed_ports:
                    lines.append(_render_port_line(port, "-", COLOR_RED))
            else:
                lines.append(f"{COLOR_RED}- 🔀 (none){COLOR_RESET}")

            if added_ports:
                for port in added_ports:
                    lines.append(_render_port_line(port, "+", COLOR_GREEN))
            else:
                lines.append(f"{COLOR_GREEN}+ 🔀 (none){COLOR_RESET}")

            if unchanged_ports:
                for port in unchanged_ports:
                    lines.append(_render_port_line(port, "", COLOR_DIM))
        elif new_ports_set:
            for port in sorted(new_ports_set):
                lines.append(_render_port_line(port, "", COLOR_DIM))

    # Volumes
    if volumes or "volumes" in changed_fields:
        if "volumes" in changed_fields:
            old_volumes_str = old_values.get("volumes", "")
            old_volume_set = set(_split_volumes(old_volumes_str))
            new_volume_set = set(_split_volumes(normalize_volumes_list(volumes)))

            removed_vols = sorted(old_volume_set - new_volume_set)
            added_vols = sorted(new_volume_set - old_volume_set)
            unchanged_vols = sorted(old_volume_set & new_volume_set)

            if removed_vols:
                for vol in removed_vols:
                    if vol and "docker.sock" not in vol:
                        formatted = format_volume_display(
                            vol, project_path, container_name
                        )
                        if formatted:
                            lines.append(f"{COLOR_RED}- 💾 {formatted}{COLOR_RESET}")
            else:
                lines.append(f"{COLOR_RED}- 💾 (none){COLOR_RESET}")

            if added_vols:
                for vol in added_vols:
                    if vol and "docker.sock" not in vol:
                        formatted = format_volume_display(
                            vol, project_path, container_name
                        )
                        if formatted:
                            lines.append(f"{COLOR_GREEN}+ 💾 {formatted}{COLOR_RESET}")
            else:
                lines.append(f"{COLOR_GREEN}+ 💾 (none){COLOR_RESET}")

            if unchanged_vols:
                for vol in unchanged_vols:
                    if vol and "docker.sock" not in vol:
                        formatted = format_volume_display(
                            vol, project_path, container_name, dim=True
                        )
                        if formatted:
                            lines.append(f"💾 {formatted}")
        elif volumes:
            volume_list = _split_volumes(normalize_volumes_list(volumes))

            for vol in volume_list:
                if vol and "docker.sock" not in vol:
                    formatted = format_volume_display(
                        vol, project_path, container_name, dim=True
                    )
                    if formatted:
                        lines.append(f"💾 {formatted}")

    # Print all lines
    for line in lines:
        print(line, file=sys.stderr)


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
            sys.argv[12] if len(sys.argv) > 12 else "",
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
    elif command == "compare_configs":
        compare_configs(
            sys.argv[2],
            sys.argv[3],
            sys.argv[4] if len(sys.argv) > 4 else "",
            sys.argv[5] if len(sys.argv) > 5 else "",
            sys.argv[6] if len(sys.argv) > 6 else "",
            sys.argv[7] if len(sys.argv) > 7 else "",
            sys.argv[8] if len(sys.argv) > 8 else "",
            sys.argv[9] if len(sys.argv) > 9 else "",
        )
    elif command == "format_config_display":
        format_config_display(
            sys.argv[2] if len(sys.argv) > 2 else "",
            sys.argv[3] if len(sys.argv) > 3 else "",
            sys.argv[4] if len(sys.argv) > 4 else "",
            sys.argv[5] if len(sys.argv) > 5 else "",
            sys.argv[6] if len(sys.argv) > 6 else "",
            sys.argv[7] if len(sys.argv) > 7 else "",
            sys.argv[8] if len(sys.argv) > 8 else "",
            sys.argv[9] if len(sys.argv) > 9 else "",
        )
    elif command == "normalize_volumes":
        normalize_volumes(
            sys.argv[2] if len(sys.argv) > 2 else "",
            sys.argv[3] if len(sys.argv) > 3 else "",
            sys.argv[4] if len(sys.argv) > 4 else "",
        )
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
