#!/usr/bin/env bash
#
# kernel-get.sh - Interactive Linux Kernel Source Downloader
#
# Fetches upstream Linux kernel source archives from kernel.org (mainline,
# stable, and longterm releases), downloads the archive, and extracts it
# into the project directory for macOS LLVM kernel builds.
#
# Usage:
#   ./kernel-get.sh [options]
#
# Options:
#   -t, --type <mainline|stable|longterm|custom>  Kernel release category
#   -M, --major <N>                               Major version (for longterm/custom, e.g. 6)
#   -m, --minor <N>                               Minor version (for longterm/custom, e.g. 12)
#   -v, --version <X.Y.Z>                         Exact kernel version string (e.g. 6.12.111)
#   -o, --dir <path>                              Output directory for download/extraction (default: current directory)
#   -k, --keep-archive                            Keep downloaded archive file after extracting
#   -f, --force                                   Overwrite existing extracted directory if present
#   --no-extract                                  Download archive only without extracting
#   -h, --help                                    Show this help message
#

set -e

# Record start time
START_TIME=$(date +%s)

# Cleanup trap to print execution summary
cleanup() {
    local exit_code=$?
    local end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))

    if [ $exit_code -ne 0 ] && [ $exit_code -ne 130 ]; then
        echo ""
        echo "=================================================="
        echo " KERNEL-GET STATUS: FAILED (Exit code: $exit_code)"
        echo " Total Time: ${elapsed}s"
        echo "=================================================="
    fi
}
trap cleanup EXIT

# Default values
TYPE_ARG=""
MAJOR_ARG=""
MINOR_ARG=""
VERSION_ARG=""
OUTPUT_DIR="."
KEEP_ARCHIVE=false
FORCE_OVERWRITE=false
NO_EXTRACT=false

usage() {
    cat <<EOF
Usage: $0 [options]

Interactive utility to fetch and extract Linux kernel sources from kernel.org.

Options:
  -t, --type <type>         Kernel category: 'mainline', 'stable', 'longterm', or 'custom'
  -M, --major <N>           Major version number (e.g. 6)
  -m, --minor <N>           Minor version number (e.g. 12)
  -v, --version <X.Y[.Z]>   Specific kernel version string (e.g. 7.2.7 or 6.12.111)
  -o, --dir <path>          Output directory (default: .)
  -k, --keep-archive        Keep downloaded tar archive after extraction
  -f, --force               Overwrite destination directory without prompting
  --no-extract              Download tarball only, skip extraction
  -h, --help                Show this help message

Examples:
  $0                        # Interactive selection menu
  $0 -t mainline            # Download latest mainline release
  $0 -t stable              # Download latest stable release
  $0 -t longterm -M 6 -m 12 # Download latest longterm 6.12.x release
  $0 -v 7.2.7               # Download specific kernel 7.2.7 release
EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--type)
            TYPE_ARG="$2"
            shift 2
            ;;
        --type=*)
            TYPE_ARG="${1#*=}"
            shift 1
            ;;
        -M|--major)
            MAJOR_ARG="$2"
            shift 2
            ;;
        --major=*)
            MAJOR_ARG="${1#*=}"
            shift 1
            ;;
        -m|--minor)
            MINOR_ARG="$2"
            shift 2
            ;;
        --minor=*)
            MINOR_ARG="${1#*=}"
            shift 1
            ;;
        -v|--version)
            VERSION_ARG="$2"
            shift 2
            ;;
        --version=*)
            VERSION_ARG="${1#*=}"
            shift 1
            ;;
        -o|--dir|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --dir=*|--output-dir=*)
            OUTPUT_DIR="${1#*=}"
            shift 1
            ;;
        -k|--keep-archive)
            KEEP_ARCHIVE=true
            shift 1
            ;;
        -f|--force)
            FORCE_OVERWRITE=true
            shift 1
            ;;
        --no-extract)
            NO_EXTRACT=true
            shift 1
            ;;
        -h|--help)
            usage
            trap - EXIT
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            usage
            trap - EXIT
            exit 1
            ;;
    esac
done

# Ensure curl and tar are available
for tool in curl tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: Required tool '$tool' is not installed or not in PATH." >&2
        exit 1
    fi
done

echo "=================================================="
echo "         Linux Kernel Source Downloader           "
echo "=================================================="

# Function to fetch kernel.org release metadata using Python 3
fetch_releases_json() {
    if command -v python3 >/dev/null 2>&1; then
        python3 - <<'EOF'
import urllib.request
import json
import sys

url = "https://www.kernel.org/releases.json"
try:
    req = urllib.request.Request(url, headers={'User-Agent': 'kernel-get.sh/1.0'})
    with urllib.request.urlopen(req, timeout=8) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        releases = data.get('releases', [])
        for r in releases:
            moniker = r.get('moniker', '')
            version = r.get('version', '')
            source = r.get('source', '')
            iseol = "1" if r.get('iseol', False) else "0"
            if source:
                print(f"{moniker}|{version}|{source}|{iseol}")
except Exception as e:
    sys.exit(1)
EOF
    fi
}

echo -n "Fetching latest release manifest from kernel.org... "
RELEASES_RAW=""
if RELEASES_RAW=$(fetch_releases_json 2>/dev/null); then
    echo "Done."
else
    echo "Notice: Could not fetch releases.json (offline or slow network); using fallback URL resolution."
    RELEASES_RAW=""
fi

# Parse releases list into arrays
MAINLINE_VER=""
MAINLINE_URL=""
STABLE_VER=""
STABLE_URL=""
LONGTERM_VERS=()
LONGTERM_URLS=()

if [ -n "$RELEASES_RAW" ]; then
    while IFS="|" read -r moniker version source iseol; do
        case "$moniker" in
            mainline)
                if [ -z "$MAINLINE_VER" ]; then
                    MAINLINE_VER="$version"
                    MAINLINE_URL="$source"
                fi
                ;;
            stable)
                if [ -z "$STABLE_VER" ]; then
                    STABLE_VER="$version"
                    STABLE_URL="$source"
                fi
                ;;
            longterm)
                if [ "$iseol" != "1" ]; then
                    LONGTERM_VERS+=("$version")
                    LONGTERM_URLS+=("$source")
                fi
                ;;
        esac
    done <<< "$RELEASES_RAW"
fi

# Resolve version and download URL based on inputs or interactive prompts
SELECTED_VER=""
DOWNLOAD_URL=""

# Helper to construct fallback CDN URL
construct_cdn_url() {
    local ver="$1"
    local major="${ver%%.*}"
    echo "https://cdn.kernel.org/pub/linux/kernel/v${major}.x/linux-${ver}.tar.xz"
}

# If specific version was supplied via CLI argument
if [ -n "$VERSION_ARG" ]; then
    SELECTED_VER="$VERSION_ARG"
    # Check if exact match exists in releases
    if [ -n "$RELEASES_RAW" ]; then
        while IFS="|" read -r moniker version source iseol; do
            if [ "$version" = "$SELECTED_VER" ]; then
                DOWNLOAD_URL="$source"
                break
            fi
        done <<< "$RELEASES_RAW"
    fi
    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL=$(construct_cdn_url "$SELECTED_VER")
    fi
fi

# If type was supplied or needs to be queried
if [ -z "$SELECTED_VER" ]; then
    if [ -z "$TYPE_ARG" ]; then
        echo ""
        echo "Select kernel release category:"
        echo "  1) Mainline  ${MAINLINE_VER:+[latest: $MAINLINE_VER]}"
        echo "  2) Stable    ${STABLE_VER:+[latest: $STABLE_VER]}"
        echo "  3) Longterm  (Select from supported branches or specify major/minor)"
        echo "  4) Custom    (Enter specific kernel version)"
        echo ""
        read -rp "Enter choice [1-4] (default: 2 - Stable): " cat_choice
        case "$cat_choice" in
            1) TYPE_ARG="mainline" ;;
            3) TYPE_ARG="longterm" ;;
            4) TYPE_ARG="custom" ;;
            2|"") TYPE_ARG="stable" ;;
            *)
                echo "Invalid selection '$cat_choice'. Defaulting to stable."
                TYPE_ARG="stable"
                ;;
        esac
    fi

    case "$TYPE_ARG" in
        mainline)
            if [ -n "$MAINLINE_VER" ]; then
                SELECTED_VER="$MAINLINE_VER"
                DOWNLOAD_URL="$MAINLINE_URL"
            else
                read -rp "Enter mainline version (e.g. 7.3-rc4): " SELECTED_VER
                DOWNLOAD_URL="https://git.kernel.org/torvalds/t/linux-${SELECTED_VER}.tar.gz"
            fi
            ;;
        stable)
            if [ -n "$STABLE_VER" ]; then
                SELECTED_VER="$STABLE_VER"
                DOWNLOAD_URL="$STABLE_URL"
            else
                read -rp "Enter stable version (e.g. 7.2.7): " SELECTED_VER
                DOWNLOAD_URL=$(construct_cdn_url "$SELECTED_VER")
            fi
            ;;
        longterm)
            # If major and minor are already provided via CLI flags
            if [ -n "$MAJOR_ARG" ] && [ -n "$MINOR_ARG" ]; then
                BRANCH_PREFIX="${MAJOR_ARG}.${MINOR_ARG}"
                # Search if there is a matching longterm release in releases.json
                for i in "${!LONGTERM_VERS[@]}"; do
                    ver="${LONGTERM_VERS[$i]}"
                    if [[ "$ver" == "$BRANCH_PREFIX."* ]]; then
                        SELECTED_VER="$ver"
                        DOWNLOAD_URL="${LONGTERM_URLS[$i]}"
                        break
                    fi
                done
                if [ -z "$SELECTED_VER" ]; then
                    SELECTED_VER="${BRANCH_PREFIX}.0"
                    DOWNLOAD_URL=$(construct_cdn_url "$SELECTED_VER")
                fi
            else
                echo ""
                echo "Available Longterm Branches:"
                idx=1
                declare -a BRANCH_MAP
                if [ ${#LONGTERM_VERS[@]} -gt 0 ]; then
                    for i in "${!LONGTERM_VERS[@]}"; do
                        ver="${LONGTERM_VERS[$i]}"
                        major_min=$(echo "$ver" | awk -F. '{print $1"."$2}')
                        echo "  $idx) Linux ${major_min}.y (latest: $ver)"
                        BRANCH_MAP[$idx]="${LONGTERM_VERS[$i]}|${LONGTERM_URLS[$i]}"
                        idx=$((idx + 1))
                    done
                fi
                echo "  $idx) Specify custom Major and Minor version"
                echo ""
                read -rp "Enter choice [1-$idx] (default: 1): " lt_choice
                lt_choice="${lt_choice:-1}"

                if [ "$lt_choice" -eq "$idx" ] || [ ${#LONGTERM_VERS[@]} -eq 0 ]; then
                    read -rp "Enter Major version (e.g. 6): " user_major
                    read -rp "Enter Minor version (e.g. 12): " user_minor
                    read -rp "Enter Patch version (optional, leave blank for latest/0): " user_patch

                    if [ -n "$user_patch" ]; then
                        SELECTED_VER="${user_major}.${user_minor}.${user_patch}"
                        DOWNLOAD_URL=$(construct_cdn_url "$SELECTED_VER")
                    else
                        BRANCH_PREFIX="${user_major}.${user_minor}"
                        for i in "${!LONGTERM_VERS[@]}"; do
                            ver="${LONGTERM_VERS[$i]}"
                            if [[ "$ver" == "$BRANCH_PREFIX."* ]]; then
                                SELECTED_VER="$ver"
                                DOWNLOAD_URL="${LONGTERM_URLS[$i]}"
                                break
                            fi
                        done
                        if [ -z "$SELECTED_VER" ]; then
                            SELECTED_VER="${BRANCH_PREFIX}.0"
                            DOWNLOAD_URL=$(construct_cdn_url "$SELECTED_VER")
                        fi
                    fi
                elif [ -n "${BRANCH_MAP[$lt_choice]}" ]; then
                    IFS="|" read -r SELECTED_VER DOWNLOAD_URL <<< "${BRANCH_MAP[$lt_choice]}"
                else
                    IFS="|" read -r SELECTED_VER DOWNLOAD_URL <<< "${BRANCH_MAP[1]}"
                fi
            fi
            ;;
        custom)
            read -rp "Enter specific Linux kernel version (e.g. 7.2.7 or 6.12.111): " SELECTED_VER
            if [ -z "$SELECTED_VER" ]; then
                echo "Error: Version cannot be empty." >&2
                exit 1
            fi
            DOWNLOAD_URL=$(construct_cdn_url "$SELECTED_VER")
            ;;
        *)
            echo "Error: Unrecognized kernel release category '$TYPE_ARG'." >&2
            exit 1
            ;;
    esac
fi

# Ensure we have a valid version and URL
if [ -z "$SELECTED_VER" ] || [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: Failed to determine kernel version or download URL." >&2
    exit 1
fi

ARCHIVE_FILENAME="$(basename "$DOWNLOAD_URL")"
EXTRACT_DIR_NAME="linux-${SELECTED_VER}"
OUTPUT_PATH="${OUTPUT_DIR%/}/${EXTRACT_DIR_NAME}"
ARCHIVE_PATH="${OUTPUT_DIR%/}/${ARCHIVE_FILENAME}"

echo ""
echo "=================================================="
echo " Download Configuration Summary"
echo "=================================================="
echo " Kernel Version   : $SELECTED_VER"
echo " Download URL     : $DOWNLOAD_URL"
echo " Archive Name     : $ARCHIVE_FILENAME"
echo " Target Directory : $OUTPUT_PATH"
echo "=================================================="
echo ""

# Check if target directory already exists
if [ -d "$OUTPUT_PATH" ] && [ "$NO_EXTRACT" = false ]; then
    if [ "$FORCE_OVERWRITE" = false ]; then
        echo "Target directory '$OUTPUT_PATH' already exists."
        read -rp "Overwrite and re-extract? (y/N): " confirm_overwrite
        case "$confirm_overwrite" in
            [yY]|[yY][eE][sS])
                echo "Removing existing directory '$OUTPUT_PATH'..."
                rm -rf "$OUTPUT_PATH"
                ;;
            *)
                echo "Skipping download & extraction. Existing directory preserved."
                trap - EXIT
                exit 0
                ;;
        esac
    else
        echo "Overwriting existing directory '$OUTPUT_PATH'..."
        rm -rf "$OUTPUT_PATH"
    fi
fi

# Download kernel archive if not already cached
mkdir -p "$OUTPUT_DIR"
if [ -f "$ARCHIVE_PATH" ]; then
    echo "Found existing cached archive: $ARCHIVE_PATH"
    read -rp "Use cached archive? (Y/n): " use_cache
    case "$use_cache" in
        [nN]|[nN][oO])
            echo "Re-downloading archive..."
            rm -f "$ARCHIVE_PATH"
            ;;
        *)
            echo "Using cached archive."
            ;;
    esac
fi

if [ ! -f "$ARCHIVE_PATH" ]; then
    echo "Downloading Linux kernel source archive..."
    if ! curl -fL --progress-bar "$DOWNLOAD_URL" -o "$ARCHIVE_PATH"; then
        echo ""
        echo "Download failed from: $DOWNLOAD_URL"
        # If .tar.xz failed, try .tar.gz fallback or vice versa
        if [[ "$DOWNLOAD_URL" == *".tar.xz" ]]; then
            FALLBACK_URL="${DOWNLOAD_URL%.tar.xz}.tar.gz"
            FALLBACK_FILE="${ARCHIVE_FILENAME%.tar.xz}.tar.gz"
            FALLBACK_PATH="${OUTPUT_DIR%/}/${FALLBACK_FILE}"
            echo "Attempting fallback to: $FALLBACK_URL"
            if curl -fL --progress-bar "$FALLBACK_URL" -o "$FALLBACK_PATH"; then
                ARCHIVE_PATH="$FALLBACK_PATH"
                ARCHIVE_FILENAME="$FALLBACK_FILE"
            else
                echo "Error: Failed to download archive." >&2
                rm -f "$ARCHIVE_PATH" "$FALLBACK_PATH" 2>/dev/null || true
                exit 1
            fi
        else
            echo "Error: Failed to download archive from $DOWNLOAD_URL." >&2
            rm -f "$ARCHIVE_PATH" 2>/dev/null || true
            exit 1
        fi
    fi
    echo "Download completed successfully."
fi

# Extraction step
if [ "$NO_EXTRACT" = false ]; then
    echo ""
    echo "Extracting $ARCHIVE_FILENAME to $OUTPUT_DIR..."
    tar -xf "$ARCHIVE_PATH" -C "$OUTPUT_DIR"
    echo "Extraction complete: $OUTPUT_PATH"

    if [ "$KEEP_ARCHIVE" = false ]; then
        echo "Removing temporary archive $ARCHIVE_PATH (use -k / --keep-archive to preserve)..."
        rm -f "$ARCHIVE_PATH"
    fi
fi

# Success banner & Next Steps
ELAPSED_TOTAL=$(( $(date +%s) - START_TIME ))
echo ""
echo "=================================================="
echo " KERNEL-GET STATUS: SUCCESS"
echo " Target Directory : $OUTPUT_PATH"
echo " Execution Time   : ${ELAPSED_TOTAL}s"
echo "=================================================="
echo ""
echo "Next Steps:"
echo " 1. Make any required kernel configuration or patches for macOS (see MACOS_BUILD_GUIDE.md):"
echo "    - scripts/Kbuild.include (APFS case-insensitivity fix)"
echo "    - arch/arm64/tools/gen-kernel-hwcaps.sh (BSD sed fix for arm64)"
echo ""
echo " 2. Configure and build the kernel using build.sh:"
echo "    ./build.sh --dir \"$OUTPUT_PATH\" --arch arm64 defconfig Image"
echo "    ./build.sh --dir \"$OUTPUT_PATH\" --arch x86_64 defconfig bzImage"
echo ""

trap - EXIT
exit 0
