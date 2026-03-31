#!/bin/sh

focusflow_repo_dir() {
    if [ -n "${FOCUSFLOW_REPO_DIR:-}" ]; then
        printf '%s\n' "$FOCUSFLOW_REPO_DIR"
        return
    fi

    if [ -n "${REPO_DIR:-}" ]; then
        printf '%s\n' "$REPO_DIR"
        return
    fi

    pwd
}

focusflow_resolve_capture_runner() {
    printf '%s\n' "${RUNNER:-swift}"
}

focusflow_readme_screenshot_contract_path() {
    if [ -n "${FOCUSFLOW_README_SCREENSHOT_CONTRACT_PATH:-}" ]; then
        printf '%s\n' "$FOCUSFLOW_README_SCREENSHOT_CONTRACT_PATH"
        return
    fi

    printf '%s\n' "$(focusflow_repo_dir)/Scripts/readme-screenshot-contract.tsv"
}

focusflow_publish_readme_screenshots() {
    focusflow_source_dir="${1:-${FOCUSFLOW_README_SCREENSHOT_SOURCE_DIR:-}}"
    focusflow_output_dir="${2:-${FOCUSFLOW_README_SCREENSHOT_OUTPUT_DIR:-}}"
    focusflow_contract_path="${3:-$(focusflow_readme_screenshot_contract_path)}"
    focusflow_tab="$(printf '\t')"

    if [ -z "$focusflow_source_dir" ]; then
        echo "focusflow_publish_readme_screenshots requires a source directory" >&2
        return 1
    fi

    if [ -z "$focusflow_output_dir" ]; then
        echo "focusflow_publish_readme_screenshots requires an output directory" >&2
        return 1
    fi

    if [ ! -f "$focusflow_contract_path" ]; then
        echo "Missing README screenshot contract: $focusflow_contract_path" >&2
        return 1
    fi

    if ! command -v sips >/dev/null 2>&1; then
        echo "sips is required to publish README screenshots" >&2
        return 1
    fi

    mkdir -p "$focusflow_output_dir"

    while IFS="$focusflow_tab" read -r focusflow_flow_id focusflow_filename focusflow_width focusflow_height || [ -n "${focusflow_flow_id:-}" ]; do
        case "${focusflow_flow_id:-}" in
            ""|\#*|flow_id)
                continue
                ;;
        esac

        if [ -z "${focusflow_filename:-}" ] || [ -z "${focusflow_width:-}" ] || [ -z "${focusflow_height:-}" ]; then
            echo "Invalid README screenshot contract row for flow: ${focusflow_flow_id:-unknown}" >&2
            return 1
        fi

        focusflow_source_path="$focusflow_source_dir/$focusflow_flow_id.png"
        focusflow_output_path="$focusflow_output_dir/$focusflow_filename"

        if [ ! -f "$focusflow_source_path" ]; then
            echo "Missing source screenshot: $focusflow_source_path" >&2
            return 1
        fi

        mkdir -p "$(dirname "$focusflow_output_path")"
        sips -z "$focusflow_height" "$focusflow_width" "$focusflow_source_path" --out "$focusflow_output_path" >/dev/null
    done < "$focusflow_contract_path"
}
