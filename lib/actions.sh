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

    clear
    read -n 1 -p "Delete $resource: $object? (y/n/f) [n]: " confirm

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
        kubectl describe pod "$object" | less_help -R
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
            ' | less_help -R
    else
        kubectl describe "$resource" "$object" | less_help -R
    fi
}

# Stream a pod's logs into fzf, spilling the uncolored stream to a file so an
# editor can be opened on the exact line under the cursor.
#
# fzf owns the view because ESC and CTRL-C return to the pod list there, which
# less cannot do -- its --lesskey-src ESC binding is silently ignored by
# less 702. CTRL-V hands off to an editor when a selection needs real copying.
#
# CTRL-H, CTRL-J, CTRL-K, CTRL-L, CTRL-N and CTRL-P are deliberately unbound:
# they are commonly claimed before the terminal sees them, so a binding on any
# of them looks broken rather than absent. Arrow keys still move the cursor.
browse_logs() {
    local pod="$1"
    local container="$2"
    local spill="$3"
    local previous="$4"

    local args=("$pod" "--follow" "--prefix" "--timestamps" "--tail=${KGP_LOG_TAIL:-5000}")
    if [[ -n "$container" ]]; then
        args+=("-c" "$container")
    else
        args+=("--all-containers" "--max-log-requests=20")
    fi
    [[ -n "$previous" ]] && args+=("--previous")

    # Opened with no user config on purpose: a 100MB buffer takes 0.14s that way
    # versus minutes with plugins loaded, and no mouse grab means the terminal's
    # own drag-select keeps working for copying.
    local editor="${KGP_LOG_EDITOR:-nvim -u NONE --noplugin}"

    # Same breadcrumb shape and colors as the other views, so the log view reads
    # as part of the tool rather than a separate screen.
    local crumbs="⎈ $(colorize YELLOW "$CONTEXT") > $(colorize YELLOW "$NAMESPACE") > $(colorize YELLOW "$pod")"
    [[ -n "$container" ]] && crumbs+=" > $(colorize YELLOW "$container")"
    [[ -n "$previous" ]] && crumbs+=" $(colorize ORANGE "(previous)")"

    local keys="$(colorize MAGENTA "ESC") back"
    keys+="  $(colorize MAGENTA "CTRL-V") editor"
    keys+="  $(colorize MAGENTA "CTRL-Y") copy"
    keys+="  $(colorize MAGENTA "TAB") select"
    keys+="  $(colorize MAGENTA "CTRL-G") end"
    keys+="  $(colorize MAGENTA "CTRL-/") full line"

    local fifo="${spill}.fifo"
    rm -f "$fifo"
    mkfifo "$fifo" || return 1

    # fzf reads through a fifo instead of a direct pipeline so that the producer
    # stays a background job this function can tear down by hand once the viewer
    # exits. As a foreground pipeline the shell would block waiting on kubectl.
    (
        {
            kubectl logs "${args[@]}" 2>&1
            print_stream_closed_eof "$pod" "$container"
        } | tee "$spill" | highlight_logs >"$fifo"
    ) &
    local producer=$!

    # Long lines are truncated rather than wrapped, so one screen row always
    # means one log line and the list stays scannable. The preview pane below
    # carries the full text of the current line, and CTRL-V opens the whole
    # stream when more than one line needs reading.
    #
    # Several options here exist to override a user's FZF_DEFAULT_OPTS rather
    # than for their own sake: tab:accept is a common default binding that would
    # close the viewer on the first TAB instead of selecting a line, --no-multi
    # would disable selection entirely, and --scheme=path scores log text badly.
    #
    # --exact turns the query into substring matching, which is what reading logs
    # wants: fuzzy scoring spreads a query like "error" across unrelated lines
    # that merely contain those letters in order. Space-separated terms still AND
    # together, and a term can opt back into fuzzy matching with a ' prefix.
    #
    # Note there is no --nth here on purpose: --with-nth already hides field 1
    # from matching, and adding --nth=2.. on top of it points at a field the
    # transformed item no longer has, which silently matches nothing.
    #
    # The editor bindings deliberately avoid ${...} around the line number:
    # fzf treats {n} as its own placeholder and would rewrite it.
    fzf \
        --ansi \
        --exact \
        --no-sort \
        --no-mouse \
        --multi \
        --no-wrap \
        --track \
        --tail="${KGP_LOG_VIEW_LINES:-200000}" \
        --scheme=default \
        --delimiter=$'\t' \
        --with-nth=2.. \
        --height=100% \
        --prompt="Logs> " \
        --preview="preview_log_line '${spill}' {1}" \
        --preview-window="down,35%,wrap,border-top" \
        --preview-label=" full line " \
        --header="${crumbs}
${keys}" \
        --bind="esc:abort" \
        --bind="tab:toggle+down" \
        --bind="ctrl-/:toggle-preview" \
        --bind="btab:toggle+up" \
        --bind="ctrl-c:abort" \
        --bind="ctrl-g:last" \
        --bind="alt-g:first" \
        --bind="load:last" \
        --bind="result:transform:[ -n {q} ] && echo || echo last" \
        --bind="ctrl-y:execute-silent(copy_log_lines {+f})+deselect-all" \
        --bind="ctrl-v:execute(lineno={1}; ${editor} \"+\$lineno\" -- '${spill}')" \
        <"$fifo" || true

    terminate_tree "$producer"
    wait "$producer" 2>/dev/null
    rm -f "$fifo"
    return 0
}

view_logs() {
    local pod="$1"
    local container="${2:-}"

    clear

    mkdir -p "$LOG_SPILL_DIR"
    local spill
    spill=$(mktemp "${LOG_SPILL_DIR}/log.XXXXXX") || return 1

    browse_logs "$pod" "$container" "$spill" ""

    # kubectl --prefix brackets every real log line, so their absence means the
    # live stream had nothing to show -- usually a restarted container.
    if ! grep -q "^\[" "$spill" 2>/dev/null; then
        browse_logs "$pod" "$container" "$spill" "previous"
    fi

    rm -f "$spill"
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

relaunch_pod() {
    local pod="$1"

    clear
    echo "Relaunch pod: $pod"
    echo "This will delete the pod and let the controller recreate it."
    read -n 1 -p "Continue? (y/n) [n]: " confirm
    echo

    confirm="${confirm,,}"
    if [[ "$confirm" == "y" ]]; then
        if kubectl delete pod "$pod" --wait=false; then
            echo "Pod '$pod' is being deleted and will be recreated by its controller."
        else
            echo "Failed to delete pod '$pod'"
        fi
    else
        echo "Aborted."
    fi

    echo "Press any key to continue..."
    read -n 1 -s
}

create_debug_pod() {
    local pod="$1"
    local debug_pod_name="${pod}-debug"

    clear
    echo "Creating debug pod from: $pod"
    echo "Debug pod name: $debug_pod_name"
    echo -n "Enter container name to debug [app]: "
    read -r container_name
    container_name="${container_name:-app}"
    echo "Overriding entrypoint for container '$container_name' to run 'sleep 3600' for debugging..."
    if kubectl get pod "$pod" -o json | \
        jq --arg name "$debug_pod_name" --arg container "$container_name" \
        '.metadata |= {name: $name, namespace: .namespace, labels: .labels} | .spec.containers |= map(if .name == $container then .command = ["sleep", "3600"] | del(.args) else . end)' | \
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
    relaunch)
        if [[ "$MODE" == "pods" ]]; then
            relaunch_pod "$target" && refresh_cache
        elif [[ "$MODE" == "objects" ]] && [[ "$RESOURCE" == "pods" ]]; then
            relaunch_pod "$target" && refresh_objects_cache "$RESOURCE"
        fi
        ;;
    esac
}

