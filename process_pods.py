#!/usr/bin/env python3
import json
import sys
from datetime import datetime, timezone
import argparse


def format_duration(seconds):
    """Format duration in seconds to human-readable format like kubectl"""
    if seconds < 0:
        return "0s"

    if seconds < 60:
        return f"{int(seconds)}s"
    elif seconds < 3600:
        return f"{int(seconds / 60)}m{int(seconds % 60)}s"
    elif seconds < 86400:
        hours = int(seconds / 3600)
        minutes = int((seconds % 3600) / 60)
        return f"{hours}h{minutes}m"
    else:
        days = int(seconds / 86400)
        hours = int((seconds % 86400) / 3600)
        return f"{days}d{hours}h"


def get_pod_status(pod):
    """Determine pod status similar to kubectl"""
    status = pod.get("status", {})
    phase = status.get("phase", "Unknown")

    # Check if pod is being deleted
    if "deletionTimestamp" in pod.get("metadata", {}):
        return "Terminating"

    # Check init containers first
    init_containers = status.get("initContainerStatuses", [])
    for i, container in enumerate(init_containers):
        state = container.get("state", {})
        if "waiting" in state:
            reason = state["waiting"].get("reason", "PodInitializing")
            if reason == "PodInitializing":
                return f"Init:{i}/{len(init_containers)}"
            return f"Init:{reason}"
        elif "terminated" in state:
            reason = state["terminated"].get("reason", "Error")
            if reason != "Completed":
                return f"Init:{reason}"

    # Check regular containers
    container_statuses = status.get("containerStatuses", [])
    if not container_statuses and phase == "Pending":
        return "Pending"

    # Count containers in various states
    running = 0
    waiting = 0
    terminated = 0
    ready = 0

    for container in container_statuses:
        if container.get("ready", False):
            ready += 1

        state = container.get("state", {})
        if "running" in state:
            running += 1
        elif "waiting" in state:
            waiting += 1
            reason = state["waiting"].get("reason")
            if reason:
                return reason
        elif "terminated" in state:
            terminated += 1
            reason = state["terminated"].get("reason", "Error")
            exit_code = state["terminated"].get("exitCode", 1)
            if exit_code != 0:
                return reason

    # Determine status based on container states
    if phase == "Running":
        if ready == len(container_statuses):
            return "Running"
        else:
            return "NotReady"
    elif phase == "Succeeded":
        return "Completed"
    elif phase == "Failed":
        return "Error"

    return phase


def get_ready_count(pod):
    """Count ready containers"""
    ready = 0

    # Count completed init containers
    init_containers = pod.get("status", {}).get("initContainerStatuses", [])
    for container in init_containers:
        state = container.get("state", {})
        if "terminated" in state and state["terminated"].get("reason") == "Completed":
            ready += 1

    # Count ready regular containers
    container_statuses = pod.get("status", {}).get("containerStatuses", [])
    for container in container_statuses:
        if container.get("ready", False):
            ready += 1

    return ready


def get_total_containers(pod):
    """Count total containers"""
    spec = pod.get("spec", {})
    init_count = len(spec.get("initContainers", []))
    container_count = len(spec.get("containers", []))
    return init_count + container_count


def get_restart_count(pod):
    """Get total restart count"""
    container_statuses = pod.get("status", {}).get("containerStatuses", [])
    return sum(container.get("restartCount", 0) for container in container_statuses)


def get_age(pod):
    """Calculate pod age"""
    now = datetime.now(timezone.utc)
    metadata = pod.get("metadata", {})
    status = pod.get("status", {})

    # For terminated pods, calculate time from start to deletion
    if "deletionTimestamp" in metadata:
        start_time = status.get("startTime", metadata.get("creationTimestamp"))
        if start_time:
            start_dt = datetime.fromisoformat(start_time.replace("Z", "+00:00"))
            deletion_dt = datetime.fromisoformat(
                metadata["deletionTimestamp"].replace("Z", "+00:00")
            )
            age_seconds = (deletion_dt - start_dt).total_seconds()
        else:
            age_seconds = 0
    else:
        # For running pods, calculate time since creation
        creation_time = metadata.get("creationTimestamp")
        if creation_time:
            creation_dt = datetime.fromisoformat(creation_time.replace("Z", "+00:00"))
            age_seconds = (now - creation_dt).total_seconds()
        else:
            age_seconds = 0

    return format_duration(age_seconds)


def process_pods(pod_data):
    """Process pod data and return formatted output"""
    pods = pod_data.get("items", [])
    output = []

    for pod in pods:
        name = pod.get("metadata", {}).get("name", "unknown")
        ready_count = get_ready_count(pod)
        total_containers = get_total_containers(pod)
        ready_display = f"{ready_count}/{total_containers}"
        status = get_pod_status(pod)
        restarts = get_restart_count(pod)
        age = get_age(pod)

        output.append(f"{name}\t{ready_display}\t{status}\t{restarts}\t{age}")

    return "\n".join(output)


def main():
    parser = argparse.ArgumentParser(description="Process kubectl pod JSON data")
    parser.add_argument(
        "input_file", nargs="?", help="Input JSON file (default: stdin)"
    )
    parser.add_argument("-o", "--output", help="Output file (default: stdout)")

    args = parser.parse_args()

    # Read input
    if args.input_file:
        with open(args.input_file, "r") as f:
            pod_data = json.load(f)
    else:
        pod_data = json.load(sys.stdin)

    # Process pods
    result = process_pods(pod_data)

    # Write output
    if args.output:
        with open(args.output, "w") as f:
            f.write(result)
    else:
        print(result)


if __name__ == "__main__":
    main()
