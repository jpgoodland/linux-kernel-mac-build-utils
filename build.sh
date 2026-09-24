#!/usr/bin/env bash
#
# build.sh - Linux Kernel Build Script using gmake and LLVM
#
# Usage:
#   ./build.sh [options] [make targets...]
#
# Options:
#   -a, --arch <arm|arm64|x86_64>  Target architecture (default: x86_64)
#   -j, --cores <N>                Number of cores/jobs for gmake (default: autodetect)
#   -h, --help                     Show this help message
#

set -e

# Prefer Homebrew LLVM and GNU tools over BSD tools on macOS
if [ -d "/opt/homebrew/opt/gnu-sed/libexec/gnubin" ]; then
    export PATH="/opt/homebrew/opt/gnu-sed/libexec/gnubin:$PATH"
fi
if [ -d "/opt/homebrew/opt/llvm/bin" ]; then
    export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
elif [ -d "/opt/homebrew/bin" ]; then
    export PATH="/opt/homebrew/bin:$PATH"
fi

# Record start time
START_TIME=$(date +%s)

# Function to calculate and print total build time on exit
cleanup() {
    local exit_code=$?
    local end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))

    echo ""
    echo "=================================================="
    if [ $exit_code -eq 0 ]; then
        echo " BUILD STATUS: SUCCESS"
    else
        echo " BUILD STATUS: FAILED (Exit code: $exit_code)"
    fi

    if [ $minutes -gt 0 ]; then
        printf " Total Build Execution Time: %dm %ds (%d seconds)\n" "$minutes" "$seconds" "$elapsed"
    else
        printf " Total Build Execution Time: %d seconds\n" "$elapsed"
    fi
    echo "=================================================="
}

# Trap EXIT signal to guarantee execution time printing
trap cleanup EXIT

# Auto-detect available CPU cores
detect_cores() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu 2>/dev/null || echo 4
    elif [ -f /proc/cpuinfo ]; then
        grep -c '^processor' /proc/cpuinfo
    else
        echo 4
    fi
}

DETECTED_CORES=$(detect_cores)

# Default values
ARCH_VAL=""
CORES_VAL=""
MAKE_TARGETS=()

usage() {
    echo "Usage: $0 [options] [make targets...]"
    echo ""
    echo "Options:"
    echo "  -a, --arch <arch>    Target architecture: 'arm', 'arm64', or 'x86_64'"
    echo "  -j, -c, --cores <N>  Number of parallel build cores (default: $DETECTED_CORES)"
    echo "  -d, --dir <path>     Path to Linux kernel directory (default: autodetect)"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -a x86_64 -j 8"
    echo "  $0 --arch arm64 --cores 16 defconfig"
    echo "  $0 --dir linux-7.2.7 --arch arm64 --cores 10 Image"
    echo "  $0 (interactive prompt mode)"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--arch)
            ARCH_VAL="$2"
            shift 2
            ;;
        --arch=*)
            ARCH_VAL="${1#*=}"
            shift 1
            ;;
        -j|-c|--cores)
            CORES_VAL="$2"
            shift 2
            ;;
        --cores=*)
            CORES_VAL="${1#*=}"
            shift 1
            ;;
        -d|--dir)
            KERNEL_DIR="$2"
            shift 2
            ;;
        --dir=*)
            KERNEL_DIR="${1#*=}"
            shift 1
            ;;
        -h|--help)
            usage
            trap - EXIT
            exit 0
            ;;
        *)
            MAKE_TARGETS+=("$1")
            shift 1
            ;;
    esac
done

# Interactive architecture selection if not provided via flags
if [ -z "$ARCH_VAL" ]; then
    echo "=================================================="
    echo "       Linux Kernel Build Configuration           "
    echo "=================================================="
    echo "Select target architecture:"
    echo "  1) x86_64"
    echo "  2) ARM (arm64 / AArch64)"
    echo "  3) ARM (32-bit)"
    read -rp "Enter choice [1-3] (default: 1): " arch_choice
    case "$arch_choice" in
        2) ARCH_VAL="arm64" ;;
        3) ARCH_VAL="arm" ;;
        1|"") ARCH_VAL="x86_64" ;;
        *)
            ARCH_VAL="$arch_choice"
            ;;
    esac
fi

# Normalize architecture string
case "$ARCH_VAL" in
    x86_64|x86|amd64)
        TARGET_ARCH="x86_64"
        ;;
    arm64|aarch64)
        TARGET_ARCH="arm64"
        ;;
    arm|armv7*|arm32)
        TARGET_ARCH="arm"
        ;;
    *)
        echo "Warning: Unrecognized architecture '$ARCH_VAL'. Passing directly to Kbuild as ARCH=$ARCH_VAL."
        TARGET_ARCH="$ARCH_VAL"
        ;;
esac

# Interactive cores selection if not provided via flags
if [ -z "$CORES_VAL" ]; then
    read -rp "Enter number of cores to use [1-$DETECTED_CORES] (default: $DETECTED_CORES): " user_cores
    if [ -n "$user_cores" ] && [[ "$user_cores" =~ ^[0-9]+$ ]]; then
        CORES_VAL="$user_cores"
    else
        CORES_VAL="$DETECTED_CORES"
    fi
fi

# Check for gmake binary
MAKE_CMD="gmake"
if ! command -v "$MAKE_CMD" >/dev/null 2>&1; then
    if command -v make >/dev/null 2>&1; then
        echo "Note: 'gmake' command not found, falling back to 'make'."
        MAKE_CMD="make"
    else
        echo "Error: Neither 'gmake' nor 'make' command was found in PATH." >&2
        exit 1
    fi
fi

# Locate Linux kernel directory
if [ -n "$KERNEL_DIR" ]; then
    if [ ! -f "$KERNEL_DIR/Makefile" ]; then
        echo "Error: Specified kernel directory '$KERNEL_DIR' does not contain a Makefile." >&2
        exit 1
    fi
elif [ -f "Makefile" ]; then
    KERNEL_DIR="."
elif [ -d "linux-7.2" ] && [ -f "linux-7.2/Makefile" ]; then
    KERNEL_DIR="linux-7.2"
elif [ -f "../Makefile" ]; then
    KERNEL_DIR=".."
else
    echo "Warning: Could not locate kernel Makefile in current directory or linux-7.2."
    KERNEL_DIR="."
fi

# Set host include flags for macOS compatibility (e.g., elf.h support)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRA_ARGS=()
if [ -d "$SCRIPT_DIR/host-include" ]; then
    HOST_INC_FLAGS="-Wno-macro-redefined -include $SCRIPT_DIR/host-include/host_fix.h -I$SCRIPT_DIR/host-include"
    EXTRA_ARGS+=("HOSTCFLAGS=$HOST_INC_FLAGS")
fi

echo ""
echo "=================================================="
echo " Starting Kernel Build with LLVM"
echo "=================================================="
echo " Make Tool : $MAKE_CMD"
echo " Arch      : $TARGET_ARCH"
echo " Jobs      : $CORES_VAL"
echo " Compiler  : LLVM=1"
echo " Directory : $KERNEL_DIR"
if [ ${#MAKE_TARGETS[@]} -gt 0 ]; then
    echo " Targets   : ${MAKE_TARGETS[*]}"
fi
echo "=================================================="
echo ""

# Execute build command
"$MAKE_CMD" -C "$KERNEL_DIR" ARCH="$TARGET_ARCH" LLVM=1 -j"$CORES_VAL" "${EXTRA_ARGS[@]}" "${MAKE_TARGETS[@]}"

