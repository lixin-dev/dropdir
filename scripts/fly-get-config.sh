#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: fly-get-config.sh APP {DROPDIR_TOKEN|DROPDIR_TITLE}" >&2
    exit 2
fi

app=$1
variable=$2
case "$variable" in
    DROPDIR_TOKEN|DROPDIR_TITLE) ;;
    *)
        echo "Unsupported variable: $variable" >&2
        exit 2
        ;;
esac

command -v flyctl >/dev/null || {
    echo "get-config requires flyctl" >&2
    exit 1
}
command -v jq >/dev/null || {
    echo "get-config requires jq" >&2
    exit 1
}

machines=$(flyctl machines list --json --app "$app")
machine_id=$(jq -r '[.[] | select(.state == "started")][0].id // .[0].id // empty' <<<"$machines")
if [[ -z "$machine_id" ]]; then
    echo "No Fly Machine found for app '$app'; deploy the app first." >&2
    exit 1
fi

state=$(jq -r --arg id "$machine_id" '.[] | select(.id == $id) | .state' <<<"$machines")
attempt=0
while [[ "$state" == "starting" || "$state" == "stopping" ]]; do
    if (( attempt >= 30 )); then
        echo "Timed out waiting for Machine $machine_id to finish its $state transition." >&2
        exit 1
    fi
    sleep 2
    machines=$(flyctl machines list --json --app "$app")
    state=$(jq -r --arg id "$machine_id" '.[] | select(.id == $id) | .state' <<<"$machines")
    ((attempt += 1))
done

if [[ "$state" != "started" ]]; then
    case "$state" in
        created|stopped|suspended)
            flyctl machine start "$machine_id" --app "$app"
            ;;
        *)
            echo "Machine $machine_id is in unsupported state '$state'." >&2
            exit 1
            ;;
    esac
fi

for ((attempt = 0; attempt < 30; attempt++)); do
    machines=$(flyctl machines list --json --app "$app")
    state=$(jq -r --arg id "$machine_id" '.[] | select(.id == $id) | .state' <<<"$machines")
    [[ "$state" == "started" ]] && break
    sleep 2
done
if [[ "$state" != "started" ]]; then
    echo "Machine $machine_id did not reach started state (current state: $state)." >&2
    exit 1
fi

flyctl ssh console \
    --app "$app" \
    --machine "$machine_id" \
    --pty=false \
    --command "printenv $variable"
