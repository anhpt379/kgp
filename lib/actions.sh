#!/bin/bash
# ============================================================================
# Action functions (exec, delete, describe, logs, etc.)
# ============================================================================

exec_shell() {
    local pod="$1"
    local container="${2:-}"

    clear
    local exec_cmd="kubectl exec -it $pod"
    [[ -n "$container" ]] && exec_cmd+=" -c $container"
    exec_cmd+=" -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'"

    echo "Executing into ${container:+container: $container in }pod: $pod"

    if eval "$exec_cmd"; then
        return 0
    else
        echo "Failed to exec into ${container:+container: $container in }pod: $pod"
        echo "Press any key to continue..."
        read -n 1 -s
        return 1
    fi
}

delete_object() {
    local resource="$1"
    local object="$2"

    read -p -n 1 "Confirm delete? (y/n/f) [n]: " confirm
    clear

    # Normalize input to lowercase
    confirm="${confirm,,}"

    case "$confirm" in
    y | yes)
        kubectl delete "$resource" "$object"
        ;;
    f | force)
        kubectl delete "$resource" "$object" --force --grace-period=0
        ;;
    n | no | "")
        echo "Aborted."
        return 1
        ;;
    *)
        echo "Invalid input. Aborted."
        return 1
        ;;
    esac
}

describe_object() {
    local resource="$1"
    local object="$2"

    clear
    echo "Describing $resource: $object"

    if [[ "$resource" == "pod" ]]; then
        kubectl describe pod "$object" | less_help -R +F
    elif [[ "$resource" == "container" ]]; then
        load_state
        kubectl describe pod "$POD" |
            awk -v container="$object" '
                /^Containers:/ || /^Init Containers:/ { in_containers = 1 }
                in_containers && $0 ~ "^  " container ":$" {
                    found = 1
                    print $0
                    next
                }
                found && /^  [^ ]+:$/ && $0 !~ "^    " { found = 0 }
                found && /^[^ ]/ { found = 0; in_containers = 0 }
                found { print }
            ' | less_help -R +F
    else
        kubectl describe "$resource" "$object" | less_help -R +F
    fi
}

view_logs() {
    local pod="$1"
    local container="${2:-}"

    clear
    local args=("$pod" "--follow" "--prefix" "--timestamps")
    [[ -n "$container" ]] && args+=("-c" "$container") || args+=("--all-containers" "--max-log-requests=20")

    if {
        kubectl logs "${args[@]}" 2>&1
        print_stream_closed_eof "$pod" "$container"
    } | highlight_logs | (less_help -R +F || true); then
        return 0
    else
        {
            kubectl logs "${args[@]}" --previous 2>&1
            print_stream_closed_eof "$pod" "$container"
        } | highlight_logs | (less_help -R +F || true)
    fi
}

scale_object() {
    local resource="$1"
    local object="$2"

    clear
    echo "Current replicas for $resource/$object:"
    kubectl get "$resource" "$object" -o jsonpath='{.spec.replicas}'
    echo
    echo -n "Enter new replica count: "
    read -r replicas

    if [[ "$replicas" =~ ^[0-9]+$ ]]; then
        kubectl scale "$resource" "$object" --replicas="$replicas"
    else
        echo "Invalid replica count"
        echo "Press any key to continue..."
        read -n 1 -s
    fi
}

edit_object() {
    local resource="$1"
    local object="$2"

    clear
    echo "Editing $resource/$object"
    kubectl edit $resource "$object"
}

create_debug_pod() {
    local pod="$1"
    local debug_pod_name="${pod}-debug"

    clear
    echo "Creating debug pod from: $pod"
    echo "Debug pod name: $debug_pod_name"
    echo -n "Enter container name to modify [app]: "
    read -r container_name
    container_name="${container_name:-app}"

    echo "Creating $debug_pod_name with container '$container_name' running 'sleep 3600'..."

    if kubectl get pod "$pod" -o json | \
        jq --arg name "$debug_pod_name" --arg container "$container_name" \
        '.metadata |= {name: $name, namespace: .namespace, labels: .labels} | .spec |= (del(.nodeName) | .containers |= map(if .name == $container then .args = ["sleep", "3600"] else . end))' | \
        kubectl apply -f -; then
        echo "Debug pod '$debug_pod_name' created successfully!"
        refresh_cache
    else
        echo "Failed to create debug pod"
    fi

    echo "Press any key to continue..."
    read -n 1 -s
}

dispatch() {
    local action="$1"
    local target="$2"
    load_state

    case "$action" in
    enter)
        if [[ "$MODE" == "pods" ]]; then
            save_state "containers" "$target"
        elif [[ "$MODE" == "contexts" ]]; then
            save_state "pods"
            switch_context "$target"
            refresh_cache
        elif [[ "$MODE" == "resources" ]]; then
            local resource=$(echo "$target" | awk '{print $1}')
            save_state "objects" "" "$resource"
            refresh_objects_cache "$resource"
        elif [[ "$MODE" == "objects" ]]; then
            describe_object "$RESOURCE" "$target"
        fi
        ;;
    exec)
        if [[ "$MODE" == "pods" ]]; then
            exec_shell "$target"
        elif [[ "$MODE" == "containers" ]]; then
            exec_shell "$POD" "$target"
        elif [[ "$MODE" == "objects" ]] && [[ "$RESOURCE" == "pods" ]]; then
            exec_shell "$target"
        fi
        ;;
    describe)
        if [[ "$MODE" == "pods" ]]; then
            describe_object "pod" "$target"
        elif [[ "$MODE" == "containers" ]]; then
            describe_object "container" "$target"
        elif [[ "$MODE" == "objects" ]]; then
            describe_object "$RESOURCE" "$target"
        fi
        ;;
    delete)
        if [[ "$MODE" == "pods" ]]; then
            delete_object "pod" "$target" && refresh_cache
        elif [[ "$MODE" == "objects" ]]; then
            delete_object "$RESOURCE" "$target" && refresh_objects_cache "$RESOURCE"
        fi
        ;;
    logs)
        if [[ "$MODE" == "pods" ]]; then
            view_logs "$target"
        elif [[ "$MODE" == "containers" ]]; then
            view_logs "$POD" "$target"
        elif [[ "$MODE" == "objects" ]] && [[ "$RESOURCE" == "pods" ]]; then
            view_logs "$target"
        fi
        ;;
    refresh)
        if [[ "$MODE" == "objects" ]]; then
            refresh_objects_cache "$RESOURCE"
        else
            refresh_cache
        fi
        ;;
    back)
        if [[ "$MODE" == "containers" ]]; then
            save_state "pods"
        elif [[ "$MODE" == "contexts" ]]; then
            save_state "pods"
        elif [[ "$MODE" == "resources" ]]; then
            save_state "pods"
        elif [[ "$MODE" == "objects" ]]; then
            save_state "resources"
        fi
        ;;
    contexts)
        save_state "contexts"
        ;;
    resources)
        save_state "resources"
        ;;
    scale)
        if [[ "$MODE" == "objects" ]] && [[ "$RESOURCE" =~ ^(Deployments|StatefulSets|DaemonSets|ReplicaSets)$ ]]; then
            scale_object "$RESOURCE" "$target"
            refresh_objects_cache "$RESOURCE"
        fi
        ;;
    yaml)
        if [[ "$MODE" == "pods" ]]; then
            edit_object "pod" "$target"
        elif [[ "$MODE" == "containers" ]]; then
            edit_object "pod" "$POD"
        elif [[ "$MODE" == "objects" ]]; then
            edit_object "$RESOURCE" "$target"
        else
            echo "Editing YAML not available in this mode"
            echo "Press any key to continue..."
            read -n 1 -s
        fi
        ;;
    debug)
        if [[ "$MODE" == "pods" ]]; then
            create_debug_pod "$target"
        elif [[ "$MODE" == "objects" ]] && [[ "$RESOURCE" == "pods" ]]; then
            create_debug_pod "$target"
        fi
        ;;
    esac
}

