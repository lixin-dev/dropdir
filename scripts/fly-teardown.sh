#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: fly-teardown.sh APP" >&2
    exit 2
fi

app=$1
command -v flyctl >/dev/null || {
    echo "teardown requires flyctl" >&2
    exit 1
}
command -v jq >/dev/null || {
    echo "teardown requires jq" >&2
    exit 1
}

mapfile -t machine_ids < <(flyctl machines list --json --app "$app" | jq -r '.[].id')
for machine_id in "${machine_ids[@]}"; do
    flyctl machine destroy "$machine_id" --app "$app" --force
done

mapfile -t volume_ids < <(flyctl volumes list --json --app "$app" | jq -r '.[].id')
for volume_id in "${volume_ids[@]}"; do
    flyctl volumes destroy "$volume_id" --app "$app" --yes
done

flyctl apps destroy "$app" --yes
