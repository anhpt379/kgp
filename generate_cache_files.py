#!/usr/bin/env python3
import json
import os
import sys
import argparse
from datetime import datetime, timezone
from tabulate import tabulate

# ANSI color codes
COLORS = {
    "RED": "\033[91m",
    "GREEN": "\033[92m",
    "YELLOW": "\033[93m",
    "BLUE": "\033[94m",
    "CYAN": "\033[96m",
    "WHITE": "\033[97m",
    "GRAY": "\033[90m",
    "RESET": "\033[0m",
}


def colorize(color, text):
    """Apply color to text"""
    return f"{COLORS[color]}{text}{COLORS['RESET']}"


def colorize_entire_row(color, row_data):
    """Apply color to entire row"""
    return [f"{COLORS[color]}{cell}{COLORS['RESET']}" for cell in row_data]


def format_duration(seconds):
    """Format duration to human-readable format"""
    if seconds < 60:
        return f"{int(seconds)}s"
    elif seconds < 3600:
        return f"{int(seconds/60)}m{int(seconds%60)}s"
    elif seconds < 86400:
        return f"{int(seconds/3600)}h{int((seconds%3600)/60)}m"
    else:
        return f"{int(seconds/86400)}d{int((seconds%86400)/3600)}h"


def get_container_state_info(state):
    """Extract ready status and state from container state"""
    if state.get("running"):
        return "true", "Running"
    elif state.get("waiting"):
        return "false", state["waiting"].get("reason", "Waiting")
    elif state.get("terminated"):
        reason = state["terminated"].get("reason", "Terminated")
        return "true" if reason == "Completed" else "false", reason
    return "false", "Unknown"


def get_pod_status(pod):
    """Determine pod status similar to kubectl"""
    status = pod.get("status", {})
    phase = status.get("phase", "Unknown")

    if "deletionTimestamp" in pod.get("metadata", {}):
        return "Terminating"

    # Check init containers
    init_containers = status.get("initContainerStatuses", [])
    for i, container in enumerate(init_containers):
        state = container.get("state", {})
        if "waiting" in state:
            reason = state["waiting"].get("reason", "PodInitializing")
            return (
                f"Init:{i}/{len(init_containers)}"
                if reason == "PodInitializing"
                else f"Init:{reason}"
            )
        elif "terminated" in state and state["terminated"].get("reason") != "Completed":
            return f"Init:{state['terminated'].get('reason', 'Error')}"

    # Check regular containers
    container_statuses = status.get("containerStatuses", [])
    ready_count = sum(1 for c in container_statuses if c.get("ready", False))

    for container in container_statuses:
        state = container.get("state", {})
        if "waiting" in state:
            reason = state["waiting"].get("reason")
            if reason:
                return reason
        elif "terminated" in state:
            reason = state["terminated"].get("reason", "Error")
            if state["terminated"].get("exitCode", 1) != 0:
                return reason

    if phase == "Running":
        return "Running" if ready_count == len(container_statuses) else "NotReady"
    elif phase == "Succeeded":
        return "Completed"
    elif phase == "Failed":
        return "Error"

    return phase


def get_pod_age(pod):
    """Calculate pod age"""
    now = datetime.now(timezone.utc)
    metadata = pod.get("metadata", {})
    creation_time = metadata.get("creationTimestamp")

    if creation_time:
        creation_dt = datetime.fromisoformat(creation_time.replace("Z", "+00:00"))
        age_seconds = (now - creation_dt).total_seconds()
        return format_duration(age_seconds)

    return "0s"


def get_row_color_for_pod_status(status):
    """Determine row color based on pod status"""
    if any(s in status for s in ["Error", "Failed", "CrashLoopBackOff"]):
        return "RED"
    elif any(s in status for s in ["Completed", "Terminated", "Succeeded"]):
        return "GRAY"
    else:
        return None


def get_row_color_for_container_status(status):
    """Determine row color based on container status"""
    if status in ["Error", "CrashLoopBackOff", "OOMKilled"]:
        return "RED"
    elif status in ["Completed", "Terminated"]:
        return "GRAY"
    else:
        return None


def process_pods(data):
    """Process pods and return table data"""
    table_data = []

    for pod in data.get("items", []):
        name = pod.get("metadata", {}).get("name", "unknown")
        spec = pod.get("spec", {})
        status = pod.get("status", {})

        init_count = len(spec.get("initContainers", []))
        container_count = len(spec.get("containers", []))
        total_containers = init_count + container_count

        # Count ready containers
        ready_count = 0
        for container in status.get("initContainerStatuses", []):
            state = container.get("state", {})
            if (
                "terminated" in state
                and state["terminated"].get("reason") == "Completed"
            ):
                ready_count += 1

        for container in status.get("containerStatuses", []):
            if container.get("ready", False):
                ready_count += 1

        ready_display = f"{ready_count}/{total_containers}"
        pod_status = get_pod_status(pod)
        restarts = sum(
            c.get("restartCount", 0) for c in status.get("containerStatuses", [])
        )
        age = get_pod_age(pod)

        # Create row data without colors first
        row_data = [name, ready_display, pod_status, str(restarts), age]

        # Determine if entire row should be colored
        row_color = get_row_color_for_pod_status(pod_status)

        if row_color:
            colored_row = colorize_entire_row(row_color, row_data)
        else:
            # Apply individual colors for non-RED/GRAY statuses
            colored_row = [
                colorize("WHITE", name),
                colorize(
                    (
                        "GREEN"
                        if ready_count == total_containers and total_containers > 0
                        else "YELLOW"
                    ),
                    ready_display,
                ),
                colorize("GREEN" if pod_status == "Running" else "YELLOW", pod_status),
                colorize("YELLOW" if int(restarts) > 0 else "WHITE", str(restarts)),
                age,
            ]

        table_data.append(colored_row)

    return table_data


def process_containers(data):
    """Process containers and return table data"""
    table_data = []

    for pod in data.get("items", []):
        pod_name = pod.get("metadata", {}).get("name", "unknown")
        spec = pod.get("spec", {})
        status = pod.get("status", {})

        # Process init containers
        init_containers = spec.get("initContainers", [])
        init_statuses = {s["name"]: s for s in status.get("initContainerStatuses", [])}

        for container in init_containers:
            name = container["name"]
            if name in init_statuses:
                ready, state_desc = get_container_state_info(
                    init_statuses[name].get("state", {})
                )
                if (
                    init_statuses[name]
                    .get("state", {})
                    .get("terminated", {})
                    .get("reason")
                    == "Completed"
                ):
                    ready = "true"

                # Create row data without colors first
                row_data = [pod_name, name, ready, state_desc, container["image"]]

                # Determine if entire row should be colored
                row_color = get_row_color_for_container_status(state_desc)

                if row_color:
                    colored_row = colorize_entire_row(row_color, row_data)
                else:
                    # Apply individual colors for non-RED/GRAY statuses
                    colored_row = [
                        colorize("WHITE", pod_name),
                        colorize("WHITE", name),
                        colorize("GREEN" if ready.lower() == "true" else "RED", ready),
                        colorize(
                            "GREEN" if state_desc == "Running" else "YELLOW", state_desc
                        ),
                        colorize("GRAY", container["image"]),
                    ]

                table_data.append(colored_row)

        # Process regular containers
        containers = spec.get("containers", [])
        container_statuses = {s["name"]: s for s in status.get("containerStatuses", [])}

        for container in containers:
            name = container["name"]
            if name in container_statuses:
                ready = str(container_statuses[name].get("ready", False)).lower()
                _, state_desc = get_container_state_info(
                    container_statuses[name].get("state", {})
                )

                # Create row data without colors first
                row_data = [pod_name, name, ready, state_desc, container["image"]]

                # Determine if entire row should be colored
                row_color = get_row_color_for_container_status(state_desc)

                if row_color:
                    colored_row = colorize_entire_row(row_color, row_data)
                else:
                    # Apply individual colors for non-RED/GRAY statuses
                    colored_row = [
                        colorize("WHITE", pod_name),
                        colorize("WHITE", name),
                        colorize("GREEN" if ready == "true" else "RED", ready),
                        colorize(
                            "GREEN" if state_desc == "Running" else "YELLOW", state_desc
                        ),
                        colorize("GRAY", container["image"]),
                    ]

                table_data.append(colored_row)

    return table_data


def main():
    parser = argparse.ArgumentParser(description="Process Kubernetes pod data")
    parser.add_argument(
        "-i", "--input_file", nargs="?", help="Input JSON file (default: stdin)"
    )
    parser.add_argument("-o", "--output_dir", help="Output directory")
    args = parser.parse_args()

    # Read input
    try:
        if args.input_file:
            with open(args.input_file, "r") as f:
                data = json.load(f)
        else:
            data = json.load(sys.stdin)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"Error reading input: {e}", file=sys.stderr)
        sys.exit(1)

    # Process and format pods
    pod_data = process_pods(data)
    pod_headers = [
        colorize("WHITE", "NAME"),
        colorize("WHITE", "READY"),
        colorize("WHITE", "STATUS"),
        colorize("WHITE", "RESTARTS"),
        colorize("WHITE", "AGE"),
    ]

    pod_output = tabulate(
        pod_data, headers=pod_headers, tablefmt="plain", stralign="left"
    )

    with open(os.path.join(args.output_dir, "pods"), "w") as f:
        f.write(pod_output + "\n")

    # Process and format containers
    container_data = process_containers(data)
    container_headers = [
        colorize("WHITE", "POD"),
        colorize("WHITE", "NAME"),
        colorize("WHITE", "READY"),
        colorize("WHITE", "STATUS"),
        colorize("WHITE", "IMAGE"),
    ]

    container_output = tabulate(
        container_data, headers=container_headers, tablefmt="plain", stralign="left"
    )

    with open(os.path.join(args.output_dir, "containers"), "w") as f:
        f.write(container_output + "\n")


if __name__ == "__main__":
    main()
