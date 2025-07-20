#!/usr/bin/env python3
import json
import os
import sys
import argparse
from datetime import datetime, timezone

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


def process_pods(data):
    """Process pods and return formatted lines"""
    results = []
    for pod in data.get("items", []):
        name = pod.get("metadata", {}).get("name", "unknown")

        # Count containers
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

        results.append((name, ready_display, pod_status, str(restarts), age))
    return results


def process_containers(data):
    """Process containers and return formatted lines"""
    results = []
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
                results.append((pod_name, name, ready, state_desc, container["image"]))

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
                results.append((pod_name, name, ready, state_desc, container["image"]))

    return results


def colorize_pod_line(name, ready, status, restarts, age):
    """Colorize pod line based on status"""
    restarts_int = int(restarts) if restarts.isdigit() else 0
    ready_parts = ready.split("/")
    ready_count = (
        int(ready_parts[0]) if len(ready_parts) > 0 and ready_parts[0].isdigit() else 0
    )
    total_count = (
        int(ready_parts[1]) if len(ready_parts) > 1 and ready_parts[1].isdigit() else 0
    )

    if any(s in status for s in ["Error", "Failed", "CrashLoopBackOff"]):
        return colorize(
            "RED", f"{name:<50} {ready:<10} {status:<20} {restarts:<10} {age}"
        )
    elif any(s in status for s in ["Completed", "Terminated", "Succeeded"]):
        return colorize(
            "GRAY", f"{name:<50} {ready:<10} {status:<20} {restarts:<10} {age}"
        )
    elif "Pending" in status or "ContainerCreating" in status:
        return colorize(
            "YELLOW", f"{name:<50} {ready:<10} {status:<20} {restarts:<10} {age}"
        )
    elif status == "Running" and ready_count == total_count and total_count > 0:
        restart_color = "YELLOW" if restarts_int > 0 else "WHITE"
        return f"{colorize('WHITE', f'{name:<50}')} {colorize('WHITE', f'{ready:<10}')} {colorize('GREEN', f'{status:<20}')} {colorize(restart_color, f'{restarts:<10}')} {age}"
    elif "Running" in status or "NotReady" in status:
        restart_color = "YELLOW" if restarts_int > 0 else "WHITE"
        return f"{colorize('WHITE', f'{name:<50}')} {colorize('YELLOW', f'{ready:<10}')} {colorize('YELLOW', f'{status:<20}')} {colorize(restart_color, f'{restarts:<10}')} {age}"
    else:
        return f"{name:<50} {ready:<10} {status:<20} {restarts:<10} {age}"


def colorize_container_line(name, ready, status, image):
    """Colorize container line based on status"""
    if status in ["Error", "CrashLoopBackOff", "OOMKilled"]:
        return colorize("RED", f"{name:<50} {ready:<10} {status:<20} {image}")
    elif status in ["Completed", "Terminated"]:
        return colorize("GRAY", f"{name:<50} {ready:<10} {status:<20} {image}")
    elif status == "Running":
        ready_color = "GREEN" if ready.lower() == "true" else "RED"
        status_color = "GREEN" if ready.lower() == "true" else "YELLOW"
        return f"{colorize('WHITE', f'{name:<50}')} {colorize(ready_color, f'{ready:<10}')} {colorize(status_color, f'{status:<20}')} {colorize('GRAY', image)}"
    elif status in ["Waiting", "Pending", "ContainerCreating", "PodInitializing"]:
        return f"{colorize('WHITE', f'{name:<50}')} {colorize('YELLOW', f'{ready:<10}')} {colorize('YELLOW', f'{status:<20}')} {colorize('GRAY', image)}"
    else:
        return f"{name:<50} {ready:<10} {status:<20} {image}"


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

    # Process pods
    results = process_pods(data)
    header = f"{'NAME':<50} {'READY':<10} {'STATUS':<20} {'RESTARTS':<10} AGE"
    lines = [colorize("WHITE", header)] + [
        colorize_pod_line(*result) for result in results
    ]
    output_text = "\n".join(lines)
    with open(os.path.join(args.output_dir, "pods"), "w") as f:
        f.write(output_text + "\n")

    # Process containers
    results = process_containers(data)
    header = f"POD\t{'NAME':<50} {'READY':<10} {'STATUS':<20} IMAGE"
    lines = [colorize("WHITE", header)] + [
        result[0] + "\t" + colorize_container_line(*result[1:]) for result in results
    ]
    output_text = "\n".join(lines)
    with open(os.path.join(args.output_dir, "containers"), "w") as f:
        f.write(output_text + "\n")


if __name__ == "__main__":
    main()
