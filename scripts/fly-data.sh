#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: fly-data.sh {list|upload|download} APP [DIRECTORY]" >&2
    exit 2
}

[[ $# -ge 2 ]] || usage
action=$1
app=$2
directory=${3:-}

case "$action" in
    list)
        [[ $# -eq 2 ]] || usage
        ;;
    upload)
        [[ $# -eq 3 && -d "$directory" ]] || {
            echo "upload requires an existing local directory" >&2
            exit 2
        }
        source_dir=$(cd -- "$directory" && pwd -P)
        ;;
    download)
        [[ $# -eq 3 ]] || usage
        if [[ -e "$directory" && ! -d "$directory" ]]; then
            echo "download destination is not a directory: $directory" >&2
            exit 2
        fi
        ;;
    *)
        usage
        ;;
esac

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Required command not found: $1" >&2
        exit 1
    }
}

require_command flyctl
require_command jq

machines=$(flyctl machines list --json --app "$app")
machine_id=$(jq -r '[.[] | select(.state == "started")][0].id // .[0].id // empty' <<<"$machines")
if [[ -z "$machine_id" ]]; then
    echo "No Fly Machine found for app '$app'" >&2
    exit 1
fi
machine_state=$(jq -r --arg id "$machine_id" '.[] | select(.id == $id) | .state' <<<"$machines")
if [[ "$machine_state" != "started" ]]; then
    flyctl machine start "$machine_id" --app "$app"
fi

ssh_console() {
    flyctl ssh console --app "$app" --machine "$machine_id" --pty=false --command "$1"
}

sftp() {
    local subcommand=$1
    shift
    flyctl ssh sftp "$subcommand" --app "$app" --machine "$machine_id" "$@"
}

case "$action" in
    list)
        printf 'Type  Path (d=directory, f=file):\n'
        ssh_console "find /data/files -mindepth 1 -printf '%y %P\n'"
        ;;
    upload)
        suffix="$(date +%s)-$$"
        stage="/data/.dropdir-upload-$suffix"
        backup="/data/.dropdir-backup-$suffix"
        remote_archive="/data/.dropdir-upload-$suffix.tar.gz"

        require_command tar
        temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dropdir-upload.XXXXXX")
        archive="$temp_dir/payload.tar.gz"
        trap 'rm -rf -- "$temp_dir"' EXIT
        tar -czf "$archive" -C "$source_dir" .

        echo "Uploading archive to $remote_archive; active remote data is unchanged until transfer completes."
        cleanup_stage() {
            local status=$?
            trap - EXIT
            local remote_cleanup="rm -f -- '$remote_archive'"
            if [[ -n "$stage" ]]; then
                remote_cleanup="rm -rf -- '$stage' '$remote_archive'"
            fi
            if ! ssh_console "$remote_cleanup" >/dev/null; then
                echo "Warning: could not remove upload staging files from the remote machine." >&2
            fi
            rm -rf -- "$temp_dir"
            exit "$status"
        }
        trap cleanup_stage EXIT

        sftp put "$archive" "$remote_archive"
        ssh_console "mkdir -- '$stage' && tar -xzf '$remote_archive' -C '$stage'"

        ssh_console "test -d /data/files"
        ssh_console "mv -- /data/files '$backup'"
        if ! ssh_console "mv -- '$stage' /data/files"; then
            echo "Could not activate staged data; restoring previous directory." >&2
            if ssh_console "mv -- '$backup' /data/files"; then
                echo "Previous data directory restored." >&2
            else
                echo "Restore failed; previous data remains at $backup." >&2
            fi
            exit 1
        fi
        stage=""
        ssh_console "rm -f -- '$remote_archive'"
        ssh_console "rm -rf -- '$backup'"
        trap - EXIT
        rm -rf -- "$temp_dir"
        echo "Replaced remote data directory contents with '$source_dir'."
        ;;
    download)
        mkdir -p -- "$directory"
        destination_dir=$(cd -- "$directory" && pwd -P)
        require_command tar
        temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dropdir-download.XXXXXX")
        remote_archive="/data/.dropdir-download-$(date +%s)-$$.tar.gz"

        cleanup_download() {
            local status=$?
            trap - EXIT
            if ! ssh_console "rm -f -- '$remote_archive'" >/dev/null; then
                echo "Warning: could not remove remote download archive $remote_archive." >&2
            fi
            rm -rf -- "$temp_dir"
            exit "$status"
        }
        trap cleanup_download EXIT

        ssh_console "tar -czf '$remote_archive' -C /data/files ."
        sftp get "$remote_archive" "$temp_dir/payload.tar.gz"
        mkdir -- "$temp_dir/payload"
        tar -xzf "$temp_dir/payload.tar.gz" -C "$temp_dir/payload"
        cp -a -- "$temp_dir/payload/." "$destination_dir/"

        ssh_console "rm -f -- '$remote_archive'"
        trap - EXIT
        rm -rf -- "$temp_dir"
        echo "Copied remote data directory contents into '$destination_dir'."
        ;;
    *)
        usage
        ;;
esac
