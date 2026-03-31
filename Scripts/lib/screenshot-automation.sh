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

focusflow_is_positive_integer() {
    case "${1:-}" in
        ""|0|*[!0-9]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

focusflow_pngs_are_pixel_equal() {
    focusflow_left_path="${1:-}"
    focusflow_right_path="${2:-}"

    if [ ! -f "$focusflow_left_path" ] || [ ! -f "$focusflow_right_path" ]; then
        return 1
    fi

    if ! command -v swift >/dev/null 2>&1; then
        return 1
    fi

    swift - "$focusflow_left_path" "$focusflow_right_path" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

func normalizedRGBAData(from image: CGImage) -> Data? {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    var data = Data(count: bytesPerRow * height)

    let drew = data.withUnsafeMutableBytes { buffer -> Bool in
        guard let baseAddress = buffer.baseAddress,
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return false
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }

    return drew ? data : nil
}

let leftURL = URL(fileURLWithPath: CommandLine.arguments[1])
let rightURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let leftData = try? Data(contentsOf: leftURL),
      let rightData = try? Data(contentsOf: rightURL),
      let leftRep = NSBitmapImageRep(data: leftData),
      let rightRep = NSBitmapImageRep(data: rightData),
      let leftCG = leftRep.cgImage,
      let rightCG = rightRep.cgImage else {
    exit(2)
}

guard leftCG.width == rightCG.width, leftCG.height == rightCG.height else {
    exit(1)
}

guard let normalizedLeft = normalizedRGBAData(from: leftCG),
      let normalizedRight = normalizedRGBAData(from: rightCG) else {
    exit(2)
}

exit(normalizedLeft == normalizedRight ? 0 : 1)
SWIFT
}

focusflow_publish_readme_screenshots() (
    focusflow_source_dir="${1:-${FOCUSFLOW_README_SCREENSHOT_SOURCE_DIR:-}}"
    focusflow_output_dir="${2:-${FOCUSFLOW_README_SCREENSHOT_OUTPUT_DIR:-}}"
    focusflow_contract_path="${3:-$(focusflow_readme_screenshot_contract_path)}"
    focusflow_tab="$(printf '\t')"
    focusflow_stage_dir=

    if [ -z "$focusflow_source_dir" ]; then
        echo "focusflow_publish_readme_screenshots requires a source directory" >&2
        exit 1
    fi

    if [ -z "$focusflow_output_dir" ]; then
        echo "focusflow_publish_readme_screenshots requires an output directory" >&2
        exit 1
    fi

    if [ ! -f "$focusflow_contract_path" ]; then
        echo "Missing README screenshot contract: $focusflow_contract_path" >&2
        exit 1
    fi

    if ! command -v sips >/dev/null 2>&1; then
        echo "sips is required to publish README screenshots" >&2
        exit 1
    fi

    focusflow_stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/focusflow-readme-publish.XXXXXX")"

    while IFS="$focusflow_tab" read -r focusflow_flow_id focusflow_filename focusflow_width focusflow_height || [ -n "${focusflow_flow_id:-}" ]; do
        case "${focusflow_flow_id:-}" in
            ""|\#*|flow_id)
                continue
                ;;
        esac

        if [ -z "${focusflow_filename:-}" ] || [ -z "${focusflow_width:-}" ] || [ -z "${focusflow_height:-}" ]; then
            echo "Invalid README screenshot contract row for flow: ${focusflow_flow_id:-unknown}" >&2
            rm -rf "$focusflow_stage_dir"
            exit 1
        fi

        if ! focusflow_is_positive_integer "$focusflow_width" || ! focusflow_is_positive_integer "$focusflow_height"; then
            echo "Invalid README screenshot size for ${focusflow_flow_id:-unknown}: ${focusflow_width:-missing}x${focusflow_height:-missing}" >&2
            rm -rf "$focusflow_stage_dir"
            exit 1
        fi

        focusflow_source_path="$focusflow_source_dir/$focusflow_flow_id.png"
        focusflow_output_path="$focusflow_stage_dir/$focusflow_filename"

        if [ ! -f "$focusflow_source_path" ]; then
            rm -rf "$focusflow_stage_dir"
            echo "Missing source screenshot: $focusflow_source_path" >&2
            exit 1
        fi

        mkdir -p "$(dirname "$focusflow_output_path")"
        if ! sips -z "$focusflow_height" "$focusflow_width" "$focusflow_source_path" --out "$focusflow_output_path" >/dev/null; then
            rm -rf "$focusflow_stage_dir"
            echo "Failed to publish screenshot for ${focusflow_flow_id:-unknown}: $focusflow_source_path -> $focusflow_output_path" >&2
            exit 1
        fi

        focusflow_existing_output_path="$focusflow_output_dir/$focusflow_filename"
        if focusflow_pngs_are_pixel_equal "$focusflow_output_path" "$focusflow_existing_output_path"; then
            cp "$focusflow_existing_output_path" "$focusflow_output_path"
        fi
    done < "$focusflow_contract_path"

    mkdir -p "$focusflow_output_dir"
    find "$focusflow_output_dir" -mindepth 1 -maxdepth 1 ! -name '.focusflow-staging' -exec rm -rf {} +
    cp -R "$focusflow_stage_dir"/. "$focusflow_output_dir"/

    rm -rf "$focusflow_stage_dir"
)
