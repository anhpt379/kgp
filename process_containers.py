#!/usr/bin/env python3
import json
import argparse
import sys


def get_container_state_info(state):
    """Extract ready status and state description from container state."""
    if state.get("running"):
        return "true", "Running"
    elif state.get("waiting"):
        reason = state["waiting"].get("reason", "Waiting")
        return "false", reason
    elif state.get("terminated"):
        terminated = state["terminated"]
        reason = terminated.get("reason", "Terminated")
        if reason == "Completed":
            return "true", "Completed"
        elif reason == "Error":
            return "false", "Error"
        else:
            return "false", reason
    else:
        return "false", "Unknown"


def process_init_containers(pod):
    """Process init containers for a pod."""
    results = []
    pod_name = pod["metadata"]["name"]

    # Get init containers from spec
    init_containers = pod.get("spec", {}).get("initContainers", [])
    init_statuses = pod.get("status", {}).get("initContainerStatuses", [])

    # Create a map of container statuses by name for easier lookup
    status_map = {status["name"]: status for status in init_statuses}

    for container in init_containers:
        container_name = container["name"]
        status = status_map.get(container_name)

        if status:
            ready, state_desc = get_container_state_info(status.get("state", {}))
            # For init containers, adjust ready status based on termination
            if status.get("state", {}).get("terminated"):
                terminated = status["state"]["terminated"]
                if terminated.get("reason") == "Completed":
                    ready = "true"
                else:
                    ready = "false"

            results.append(
                [
                    pod_name,
                    container_name,
                    "init",
                    ready,
                    state_desc,
                    container["image"],
                ]
            )

    return results


def process_regular_containers(pod):
    """Process regular containers for a pod."""
    results = []
    pod_name = pod["metadata"]["name"]

    # Get containers from spec
    containers = pod.get("spec", {}).get("containers", [])
    container_statuses = pod.get("status", {}).get("containerStatuses", [])

    # Create a map of container statuses by name for easier lookup
    status_map = {status["name"]: status for status in container_statuses}

    for container in containers:
        container_name = container["name"]
        status = status_map.get(container_name)

        if status:
            ready = str(status.get("ready", False)).lower()
            _, state_desc = get_container_state_info(status.get("state", {}))

            results.append(
                [
                    pod_name,
                    container_name,
                    "container",
                    ready,
                    state_desc,
                    container["image"],
                ]
            )

    return results


def generate_container_list(input_file, output_file):
    """Generate container list from kubectl get pods -o json output."""
    try:
        # Read JSON data
        with open(input_file, "r") as f:
            data = json.load(f)

        # Process all pods
        all_containers = []
        for pod in data.get("items", []):
            # Process init containers
            all_containers.extend(process_init_containers(pod))

            # Process regular containers
            all_containers.extend(process_regular_containers(pod))

        # Write output as TSV
        with open(output_file, "w") as f:
            for container_info in all_containers:
                f.write("\t".join(container_info) + "\n")

    except FileNotFoundError:
        print(f"Error: Input file '{input_file}' not found", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in input file: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Process Kubernetes pod data to extract container information"
    )
    parser.add_argument(
        "input_file", help="Input JSON file (kubectl get pods -o json output)"
    )
    parser.add_argument("-o", "--output", required=True, help="Output TSV file")

    args = parser.parse_args()

    generate_container_list(args.input_file, args.output)


if __name__ == "__main__":
    main()
