#!/usr/bin/env bash
#
# mac-configure.sh - macOS System & Toolchain Setup for Linux Kernel Builds
#
# Assesses the local macOS system for required build packages, installs missing
# dependencies via Homebrew, and configures shell PATH and environment exports
# for compiling Linux kernels on Apple Silicon (and Intel) using LLVM.
#
# Usage:
#   ./mac-configure.sh [options]
#
# Options:
#   -y, --yes          Non-interactive mode (auto-install and auto-update shell profile)
#   --dry-run          Assess system and show planned changes without modifying files
#   --no-profile       Install missing brew packages but do not modify shell profiles
#   -h, --help         Show this help message
#

set -e

# Record start time
START_TIME=$(date +%s)

AUTO_YES=false
DRY_RUN=false
NO_PROFILE=false

usage() {
    cat <<EOF
Usage: $0 [options]

Configures macOS environment for building the Linux kernel with LLVM.

Options:
  -y, --yes          Proceed automatically without interactive prompts
  --dry-run          Inspect system and show missing items without applying changes
  --no-profile       Install missing Homebrew packages but skip modifying shell profile
  -h, --help         Show this help message

Examples:
  $0                 # Interactive mode
  $0 -y              # Automated configuration
  $0 --dry-run       # Audit system only
EOF
}

# Parse command line flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            AUTO_YES=true
            shift 1
            ;;
        --dry-run)
            DRY_RUN=true
            shift 1
            ;;
        --no-profile)
            NO_PROFILE=true
            shift 1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            usage
            exit 1
            ;;
    esac
done

echo "=================================================="
echo "    macOS Linux Kernel Build Environment Setup    "
echo "=================================================="

# Check operating system
OS_NAME=$(uname -s)
ARCH_NAME=$(uname -m)

if [ "$OS_NAME" != "Darwin" ]; then
    echo "Error: This configuration script is designed specifically for macOS (Darwin)." >&2
    echo "Detected OS: $OS_NAME ($ARCH_NAME)" >&2
    exit 1
fi

echo "System       : macOS ($ARCH_NAME)"

# Check Homebrew installation
if ! command -v brew >/dev/null 2>&1; then
    echo ""
    echo "Error: Homebrew is not installed or not in PATH." >&2
    echo "Please install Homebrew from https://brew.sh first:" >&2
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
    exit 1
fi

BREW_PREFIX="$(brew --prefix 2>/dev/null || echo "/opt/homebrew")"
echo "Brew Prefix  : $BREW_PREFIX"
echo ""

# Required Homebrew Packages
# -------------------------------------------------------------
# - make        : GNU Make 4.4+ (gmake) required by Kbuild
# - llvm        : Upstream Clang / LLVM toolchain (avoids Apple Clang bugs)
# - lld         : LLVM Linker (ld.lld)
# - gnu-sed     : GNU sed (avoids BSD sed in-tree regex/in-place bugs)
# - diffutils   : GNU diff utilities
# - bc          : Arbitrary precision calculator for kernel timekeeping
# - flex        : GNU Fast Lexical Analyzer Generator
# - bison       : GNU Parser Generator
# - openssl@3   : Cryptography libraries for kernel module signing & certs
# - libelf      : ELF object manipulation library (modpost, sorttable, etc.)
# - pkg-config  : Package metadata query tool
# - ncurses     : Terminal handling library for menuconfig / nconfig
# - xz          : LZMA compression utility for kernel tarballs
# - python3     : Python 3 for kernel scripts & downloader utilities

REQUIRED_PACKAGES=(
    "make"
    "llvm"
    "lld"
    "gnu-sed"
    "diffutils"
    "bc"
    "flex"
    "bison"
    "openssl@3"
    "libelf"
    "pkg-config"
    "ncurses"
    "xz"
    "python3"
)

echo "Assessing installed Homebrew packages..."
echo "--------------------------------------------------"

MISSING_PACKAGES=()
INSTALLED_PACKAGES=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
        printf "  [✓ INSTALLED] %-14s\n" "$pkg"
        INSTALLED_PACKAGES+=("$pkg")
    else
        printf "  [✗ MISSING  ] %-14s\n" "$pkg"
        MISSING_PACKAGES+=("$pkg")
    fi
done

echo "--------------------------------------------------"
echo "Installed: ${#INSTALLED_PACKAGES[@]}/${#REQUIRED_PACKAGES[@]} packages"

# Handle Missing Packages Installation
if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo ""
    echo "The following required packages are missing: ${MISSING_PACKAGES[*]}"
    if [ "$DRY_RUN" = true ]; then
        echo "[Dry-Run] Would run: brew install ${MISSING_PACKAGES[*]}"
    else
        if [ "$AUTO_YES" = false ]; then
            read -rp "Install missing packages with Homebrew now? (Y/n): " confirm_install
            case "$confirm_install" in
                [nN]|[nN][oO])
                    echo "Skipping package installation."
                    ;;
                *)
                    echo "Running: brew install ${MISSING_PACKAGES[*]}"
                    brew install "${MISSING_PACKAGES[@]}"
                    ;;
            esac
        else
            echo "Running: brew install ${MISSING_PACKAGES[*]}"
            brew install "${MISSING_PACKAGES[@]}"
        fi
    fi
else
    echo "All required Homebrew packages are already installed!"
fi

# Review and Update Shell Profile & Environment Variables
# -------------------------------------------------------------
echo ""
echo "=================================================="
echo "    Reviewing Shell Environment & PATH Setup      "
echo "=================================================="

# Determine active user shell configuration files
TARGET_PROFILES=()
if [ -f "$HOME/.bash_profile" ]; then
    TARGET_PROFILES+=("$HOME/.bash_profile")
elif [ -f "$HOME/.bashrc" ]; then
    TARGET_PROFILES+=("$HOME/.bashrc")
fi

if [ -f "$HOME/.zshrc" ]; then
    # If .zshrc does not source .bash_profile, include .zshrc
    if ! grep -q "\.bash_profile" "$HOME/.zshrc" 2>/dev/null; then
        TARGET_PROFILES+=("$HOME/.zshrc")
    fi
fi

if [ ${#TARGET_PROFILES[@]} -eq 0 ]; then
    TARGET_PROFILES+=("$HOME/.zshrc")
fi

PRIMARY_PROFILE="${TARGET_PROFILES[0]}"
echo "Primary Shell Profile : $PRIMARY_PROFILE"

# Construct standard environment block
ENV_START_MARKER="# >>> Linux Kernel Build macOS Environment >>>"
ENV_END_MARKER="# <<< Linux Kernel Build macOS Environment <<<"

read -r -d '' ENV_BLOCK <<EOF || true
$ENV_START_MARKER
# LLVM, GNU Make, GNU Sed, Bison, Flex, and Homebrew Toolchain
export PATH="$BREW_PREFIX/opt/llvm/bin:$BREW_PREFIX/opt/lld/bin:$BREW_PREFIX/opt/make/libexec/gnubin:$BREW_PREFIX/opt/gnu-sed/libexec/gnubin:$BREW_PREFIX/opt/diffutils/bin:$BREW_PREFIX/opt/bc/bin:$BREW_PREFIX/opt/bison/bin:$BREW_PREFIX/opt/flex/bin:$BREW_PREFIX/bin:$BREW_PREFIX/sbin:\$PATH"

# Compiler, Linker, and Header Flags for Linux Host Tools
export LDFLAGS="-L$BREW_PREFIX/opt/llvm/lib -L$BREW_PREFIX/opt/openssl@3/lib -L$BREW_PREFIX/opt/ncurses/lib -L$BREW_PREFIX/opt/libelf/lib \$LDFLAGS"
export CPPFLAGS="-I$BREW_PREFIX/opt/llvm/include -I$BREW_PREFIX/opt/openssl@3/include -I$BREW_PREFIX/opt/ncurses/include -I$BREW_PREFIX/opt/libelf/include \$CPPFLAGS"
export CPATH="$BREW_PREFIX/opt/ncurses/include:$BREW_PREFIX/opt/libelf/include:\$CPATH"
export LIBRARY_PATH="$BREW_PREFIX/opt/ncurses/lib:$BREW_PREFIX/opt/libelf/lib:\$LIBRARY_PATH"
export PKG_CONFIG_PATH="$BREW_PREFIX/opt/openssl@3/lib/pkgconfig:$BREW_PREFIX/opt/libelf/lib/pkgconfig:$BREW_PREFIX/opt/ncurses/lib/pkgconfig:\$PKG_CONFIG_PATH"
$ENV_END_MARKER
EOF

# Check current environment status in target profile
PROFILE_NEEDS_UPDATE=false
if [ -f "$PRIMARY_PROFILE" ]; then
    if grep -qF "$ENV_START_MARKER" "$PRIMARY_PROFILE"; then
        # Check if current content matches exactly
        CURRENT_BLOCK=$(awk "/$ENV_START_MARKER/,/$ENV_END_MARKER/" "$PRIMARY_PROFILE")
        if [ "$CURRENT_BLOCK" != "$ENV_BLOCK" ]; then
            PROFILE_NEEDS_UPDATE=true
            PROFILE_ACTION="update"
        else
            PROFILE_ACTION="none"
        fi
    else
        PROFILE_NEEDS_UPDATE=true
        PROFILE_ACTION="append"
    fi
else
    PROFILE_NEEDS_UPDATE=true
    PROFILE_ACTION="create"
fi

if [ "$NO_PROFILE" = true ]; then
    echo "Skipping shell profile update (--no-profile set)."
elif [ "$PROFILE_NEEDS_UPDATE" = false ]; then
    echo "Shell profile ($PRIMARY_PROFILE) is already fully up to date."
else
    echo "Action required for $PRIMARY_PROFILE: $PROFILE_ACTION configuration block."
    echo ""
    echo "Proposed additions / updates to $PRIMARY_PROFILE:"
    echo "--------------------------------------------------"
    echo "$ENV_BLOCK"
    echo "--------------------------------------------------"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        echo "[Dry-Run] Skipping profile write."
    else
        APPLY_PROFILE=true
        if [ "$AUTO_YES" = false ]; then
            read -rp "Apply this configuration to $PRIMARY_PROFILE? (Y/n): " confirm_profile
            case "$confirm_profile" in
                [nN]|[nN][oO])
                    APPLY_PROFILE=false
                    ;;
            esac
        fi

        if [ "$APPLY_PROFILE" = true ]; then
            BACKUP_FILE="${PRIMARY_PROFILE}.bak.$(date +%Y%m%d%H%M%S)"
            if [ -f "$PRIMARY_PROFILE" ]; then
                cp "$PRIMARY_PROFILE" "$BACKUP_FILE"
                echo "Created backup: $BACKUP_FILE"
            fi

            if [ "$PROFILE_ACTION" = "update" ]; then
                # Replace existing block
                awk -v start="$ENV_START_MARKER" -v end="$ENV_END_MARKER" -v newblock="$ENV_BLOCK" '
                    $0 ~ start { in_block=1; print newblock; next }
                    $0 ~ end { in_block=0; next }
                    !in_block { print }
                ' "$BACKUP_FILE" > "$PRIMARY_PROFILE"
            else
                # Append block
                echo "" >> "$PRIMARY_PROFILE"
                echo "$ENV_BLOCK" >> "$PRIMARY_PROFILE"
            fi
            echo "Successfully updated $PRIMARY_PROFILE."
        else
            echo "Profile update skipped by user."
        fi
    fi
fi

# Export variables for current script session to run validation checks
export PATH="$BREW_PREFIX/opt/llvm/bin:$BREW_PREFIX/opt/lld/bin:$BREW_PREFIX/opt/make/libexec/gnubin:$BREW_PREFIX/opt/gnu-sed/libexec/gnubin:$BREW_PREFIX/opt/diffutils/bin:$BREW_PREFIX/opt/bc/bin:$BREW_PREFIX/opt/bison/bin:$BREW_PREFIX/opt/flex/bin:$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$PATH"
export PKG_CONFIG_PATH="$BREW_PREFIX/opt/openssl@3/lib/pkgconfig:$BREW_PREFIX/opt/libelf/lib/pkgconfig:$BREW_PREFIX/opt/ncurses/lib/pkgconfig:$PKG_CONFIG_PATH"

# Run Toolchain Verification Diagnostics
# -------------------------------------------------------------
echo ""
echo "=================================================="
echo "          Toolchain Verification Diagnostics      "
echo "=================================================="

check_tool() {
    local name="$1"
    local cmd="$2"
    local ver_cmd="$3"
    local expected_pattern="$4"

    if command -v "$cmd" >/dev/null 2>&1; then
        local raw_ver
        raw_ver=$(eval "$ver_cmd" 2>&1 | head -n 1)
        if [[ "$raw_ver" =~ $expected_pattern ]]; then
            printf "  [✓ PASS] %-12s : %s\n" "$name" "$raw_ver"
        else
            printf "  [⚠ WARN] %-12s : %s (expected pattern: %s)\n" "$name" "$raw_ver" "$expected_pattern"
        fi
    else
        printf "  [✗ FAIL] %-12s : Command '%s' not found in PATH\n" "$name" "$cmd"
    fi
}

check_tool "GNU Make"    "make"        "make --version"                  "GNU Make (4\.[0-9]+|[5-9]\.)"
check_tool "LLVM Clang"  "clang"       "clang --version"                 "clang version (1[5-9]|[2-9][0-9])"
check_tool "LLVM Linker" "ld.lld"      "ld.lld --version"                "LLD"
check_tool "GNU Sed"     "sed"         "sed --version"                   "GNU sed"
check_tool "GNU Diff"    "diff"        "diff --version"                  "diff \(GNU diffutils\)"
check_tool "GNU Bison"   "bison"       "bison --version"                 "bison \(GNU Bison\)"
check_tool "Flex"        "flex"        "flex --version"                  "flex 2\."
check_tool "Libelf"      "pkg-config"  "pkg-config --modversion libelf"  "[0-9]"
check_tool "OpenSSL"     "pkg-config"  "pkg-config --modversion openssl" "3\."

TOTAL_TIME=$(( $(date +%s) - START_TIME ))

echo "=================================================="
echo " CONFIGURATION COMPLETE (${TOTAL_TIME}s)"
echo "=================================================="
echo ""
echo "To apply environment changes to your active terminal session, run:"
echo "  source $PRIMARY_PROFILE"
echo ""
echo "You are now ready to download and build Linux kernels on macOS:"
echo "  ./kernel-get.sh"
echo "  ./build.sh --dir linux-<version> --arch arm64 defconfig Image"
echo ""
