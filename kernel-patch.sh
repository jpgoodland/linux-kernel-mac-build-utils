#!/usr/bin/env bash
#
# kernel-patch.sh - Automated In-Tree macOS Patching for Linux Kernel Sources
#
# Applies the minimal 2 in-tree patches required to build Linux kernels on macOS:
#   1. scripts/Kbuild.include (APFS case-insensitivity fix)
#   2. arch/arm64/tools/gen-kernel-hwcaps.sh (BSD sed regex fix for arm64)
#
# Usage:
#   ./kernel-patch.sh [kernel-directory]
#

set -e

KERNEL_DIR="$1"

# If not provided, search for linux-* directory or check current directory
if [ -z "$KERNEL_DIR" ]; then
    if [ -f "Makefile" ] && [ -d "scripts" ]; then
        KERNEL_DIR="."
    else
        # Find directory matching linux-*
        CANDIDATE=$(find . -maxdepth 1 -type d -name "linux-*" | head -n 1)
        if [ -n "$CANDIDATE" ]; then
            KERNEL_DIR="$CANDIDATE"
        else
            echo "Error: No kernel directory specified and none detected (e.g. linux-X.Y.Z)." >&2
            echo "Usage: $0 <path-to-kernel-tree>" >&2
            exit 1
        fi
    fi
fi

if [ ! -f "$KERNEL_DIR/Makefile" ]; then
    echo "Error: Directory '$KERNEL_DIR' does not appear to be a Linux kernel tree (Makefile missing)." >&2
    exit 1
fi

echo "=================================================="
echo "      macOS Kernel In-Tree Patch Application      "
echo "=================================================="
echo "Target Kernel Directory: $KERNEL_DIR"
echo ""

# Use python3 to perform clean cross-platform in-place replacement
python3 - "$KERNEL_DIR" <<'EOF'
import sys
import os

kernel_dir = sys.argv[1]

# Patch 1: scripts/Kbuild.include (APFS case-insensitivity fix)
kbuild_path = os.path.join(kernel_dir, "scripts", "Kbuild.include")
if os.path.exists(kbuild_path):
    with open(kbuild_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    
    old_line = "kbuild-file = $(or $(wildcard $(src)/Kbuild),$(src)/Makefile)"
    new_line = "kbuild-file = $(or $(if $(wildcard $(src)/Kbuild/.),,$(wildcard $(src)/Kbuild)),$(src)/Makefile)"
    
    if old_line in content:
        content = content.replace(old_line, new_line)
        with open(kbuild_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("  [✓ PATCHED] scripts/Kbuild.include (APFS case-insensitivity fix applied)")
    elif new_line in content:
        print("  [✓ OK]      scripts/Kbuild.include (already patched)")
    else:
        print("  [⚠ WARN]    scripts/Kbuild.include (target line pattern not found)")
else:
    print("  [⚠ SKIP]    scripts/Kbuild.include not found")

# Patch 2: arch/arm64/tools/gen-kernel-hwcaps.sh (BSD sed fix for arm64)
hwcaps_path = os.path.join(kernel_dir, "arch", "arm64", "tools", "gen-kernel-hwcaps.sh")
if os.path.exists(hwcaps_path):
    with open(hwcaps_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    
    if r"\+" in content:
        content = content.replace(r"\+", "*")
        with open(hwcaps_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("  [✓ PATCHED] arch/arm64/tools/gen-kernel-hwcaps.sh (BSD sed fix applied)")
    else:
        print("  [✓ OK]      arch/arm64/tools/gen-kernel-hwcaps.sh (already patched or no \\+ pattern)")
else:
    print("  [ℹ INFO]    arch/arm64/tools/gen-kernel-hwcaps.sh not present for this kernel tree")

EOF

echo ""
echo "Patching completed successfully."
echo "=================================================="
