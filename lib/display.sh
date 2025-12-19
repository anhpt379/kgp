#!/bin/bash
# ============================================================================
# Display and list functions
# ============================================================================

show_pod_header() {
    echo "⎈ $(colorize YELLOW "$CONTEXT") > $(colorize YELLOW "$NAMESPACE")"
    echo "$(colorize MAGENTA "ENTER") containers  $(colorize MAGENTA "CTRL-E") exec  $(colorize MAGENTA "CTRL-D") describe  $(colorize MAGENTA "ESC") back  $(colorize MAGENTA "?") help"
}

show_container_header() {
    echo "⎈ $(colorize YELLOW "$CONTEXT") > $(colorize YELLOW "$NAMESPACE") > $(colorize YELLOW "$POD")"
    echo "$(colorize MAGENTA "ENTER") logs  $(colorize MAGENTA "CTRL-E") exec  $(colorize MAGENTA "CTRL-D") describe  $(colorize MAGENTA "ESC") back  $(colorize MAGENTA "?") help"
}

show_context_header() {
    echo "⎈ $(colorize YELLOW "$CONTEXT")"
    echo "$(colorize MAGENTA "ENTER") select  $(colorize MAGENTA "ESC") back  $(colorize MAGENTA "CTRL-C") quit  $(colorize MAGENTA "?") help"
}

show_resources_header() {
    echo "⎈ $(colorize YELLOW "$CONTEXT") > $(colorize YELLOW "$NAMESPACE")"
    echo "$(colorize MAGENTA "ENTER") view  $(colorize MAGENTA "ESC") back  $(colorize MAGENTA "CTRL-C") quit  $(colorize MAGENTA "?") help"
}

show_objects_header() {
    echo "⎈ $(colorize YELLOW "$CONTEXT") > $(colorize YELLOW "$NAMESPACE")"
    local actions="$(colorize MAGENTA "ENTER")/$(colorize MAGENTA "CTRL-D") describe  $(colorize MAGENTA "ESC") back"

    case "$RESOURCE" in
    Deployments | StatefulSets | DaemonSets) actions+="  $(colorize MAGENTA "CTRL-S") scale" ;;
    esac

    actions+="  $(colorize MAGENTA "?") help"
    echo "$actions"
}

show_help() {
    cat <<EOF
$(colorize CYAN "Context:")  $(colorize YELLOW "$CONTEXT")
$(colorize CYAN "Namespace:")  $(colorize YELLOW "$NAMESPACE")

$(colorize CYAN "Navigation:")
  $(colorize YELLOW "ENTER")         Open (containers, describe, select)
  $(colorize YELLOW "ESC")           Back
  $(colorize YELLOW "CTRL-C")        Quit
  $(colorize YELLOW "CTRL-P")        Up
  $(colorize YELLOW "CTRL-N")        Down
  $(colorize YELLOW "CTRL-B")        Page Up
  $(colorize YELLOW "CTRL-F")        Page Down

$(colorize CYAN "Views:")
  $(colorize YELLOW "CTRL-S")        Switch context
  $(colorize YELLOW "CTRL-A")        Browse all resources
  $(colorize YELLOW "CTRL-H") / $(colorize YELLOW "?")    Toggle this help

$(colorize CYAN "Actions:")
  $(colorize YELLOW "F5")            Refresh cache
  $(colorize YELLOW "CTRL-V")        View logs
  $(colorize YELLOW "CTRL-E")        Exec into pod/container
  $(colorize YELLOW "CTRL-D")        Describe resource
  $(colorize YELLOW "CTRL-Y")        Edit YAML
  $(colorize YELLOW "CTRL-K")        Delete resource
  $(colorize YELLOW "CTRL-S")        Scale (Deployments, StatefulSets, etc.)
  $(colorize YELLOW "CTRL-G")        Create debug pod (from existing pod)
EOF
}

list_pods() {
    local pods_file="${CACHE_DIR}/pods"
    [[ ! -f "$pods_file" ]] && refresh_cache
    show_pod_header
    cat "$pods_file"
}

list_containers() {
    local containers_file="${CACHE_DIR}/containers"
    [[ ! -f "$containers_file" ]] && refresh_cache
    show_container_header
    head -1 "$containers_file" | awk '{print substr($0, index($0, $2))}'
    grep "${POD}" "$containers_file" | awk '{print substr($0, index($0, $2))}'
}

list_contexts() {
    show_context_header
    echo "NAME"
    get_contexts | while read -r ctx; do
        [[ "$ctx" == "$CONTEXT" ]] && echo "$ctx $(colorize GREEN "*")" || echo "$ctx"
    done
}

list_resources() {
    show_resources_header
    echo "NAME                            DESCRIPTION"
    echo "Deployments                     Deployment controllers"
    echo "StatefulSets                    StatefulSet controllers"
    echo "DaemonSets                      DaemonSet controllers"
    echo "ReplicaSets                     ReplicaSet controllers"
    echo "Services                        Service endpoints"
    echo "Ingresses                       Ingress rules"
    echo "ConfigMaps                      Configuration data"
    echo "Secrets                         Secret data"
    echo "PersistentVolumeClaims          Storage claims"
    echo "PersistentVolumes               Storage volumes"
    echo "Jobs                            Job workloads"
    echo "CronJobs                        Scheduled jobs"
    echo "ServiceAccounts                 Service accounts"
    echo "Roles                           RBAC roles"
    echo "RoleBindings                    RBAC role bindings"
    echo "ClusterRoles                    Cluster-wide RBAC roles"
    echo "ClusterRoleBindings             Cluster-wide RBAC role bindings"
    echo "NetworkPolicies                 Network policies"
    echo "HorizontalPodAutoscalers        HPA controllers"
}

list_objects() {
    local resource="$1"
    local cache_file="${CACHE_DIR}/${resource}.cache"

    # Refresh cache if it doesn't exist
    if [[ ! -f "$cache_file" ]]; then
        refresh_objects_cache "$resource"
    fi

    show_objects_header

    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
    else
        echo "No $resource found or unable to fetch data"
    fi
}

display_data() {
    load_state
    case "$MODE" in
    pods) list_pods ;;
    containers) list_containers ;;
    contexts) list_contexts ;;
    resources) list_resources ;;
    objects) list_objects "$RESOURCE" ;;
    esac
}
