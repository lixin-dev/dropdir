app_name := env_var_or_default("APP_NAME", "dropdir")

setup:
    flyctl apps create "{{ app_name }}" --yes
    flyctl volumes create dropdir_data --size 1 --region nrt --app "{{ app_name }}" --yes --vm-cpu-kind shared --vm-cpus 1 --vm-memory 256

deploy:
    flyctl deploy --app "{{ app_name }}"

teardown:
    bash scripts/fly-teardown.sh "{{ app_name }}"

update-token token="":
    #!/usr/bin/env bash
    set -euo pipefail
    token={{ quote(token) }}
    if [[ -z "$token" ]]; then
        read -r -s -p "New token: " token
        printf '\n'
    fi
    if [[ -z "$token" ]]; then
        echo "Token cannot be empty" >&2
        exit 1
    fi
    flyctl secrets set "DROPDIR_TOKEN=$token" --app "{{ app_name }}"

update-title title="":
    #!/usr/bin/env bash
    set -euo pipefail
    title={{ quote(title) }}
    if [[ -z "$title" ]]; then
        read -r -p "New page title: " title
    fi
    if [[ -z "$title" ]]; then
        echo "Title cannot be empty" >&2
        exit 1
    fi
    flyctl secrets set "DROPDIR_TITLE=$title" --app "{{ app_name }}"

get-token:
    bash scripts/fly-get-config.sh "{{ app_name }}" DROPDIR_TOKEN

get-title:
    bash scripts/fly-get-config.sh "{{ app_name }}" DROPDIR_TITLE

list:
    bash scripts/fly-data.sh list "{{ app_name }}"

upload source_dir:
    bash scripts/fly-data.sh upload "{{ app_name }}" {{ quote(source_dir) }}

download destination_dir:
    bash scripts/fly-data.sh download "{{ app_name }}" {{ quote(destination_dir) }}
