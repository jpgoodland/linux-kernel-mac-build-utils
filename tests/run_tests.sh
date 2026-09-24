#!/usr/bin/env bash
#
# run_tests.sh - Master test runner for linux-kernel-mac-build-utils
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

START_TIME=$(date +%s)

echo "=================================================="
echo "    Linux Kernel macOS Build Utils Test Suite     "
echo "=================================================="
echo "Platform : $(uname -s) ($(uname -m))"
echo "Root     : $REPO_ROOT"
echo ""

# 1. Compile and run C host headers unit tests
echo "--- [1/2] Testing host-include C headers ---"
CC="clang"
if [ -d "/opt/homebrew/opt/llvm/bin" ]; then
    CC="/opt/homebrew/opt/llvm/bin/clang"
fi

TEST_BIN="$SCRIPT_DIR/test_host_headers_bin"
"$CC" -Wall -Wextra -Werror \
    -I"$REPO_ROOT/host-include" \
    -include "$REPO_ROOT/host-include/host_fix.h" \
    "$SCRIPT_DIR/test_host_headers.c" \
    -o "$TEST_BIN"

"$TEST_BIN"
rm -f "$TEST_BIN"
echo ""

# 2. Run Shell Scripts Test Suite
echo "--- [2/2] Testing utility shell scripts ---"
bash "$SCRIPT_DIR/test_scripts.sh"
echo ""

ELAPSED=$(( $(date +%s) - START_TIME ))
echo "=================================================="
echo " ALL TESTS COMPLETED SUCCESSFULLY (${ELAPSED}s)"
echo "=================================================="
