#!/usr/bin/env bash
#
# test_scripts.sh - Unit and integration tests for shell scripts
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FAILED_TESTS=0
TOTAL_TESTS=0

run_test() {
    local test_name="$1"
    shift
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    printf "  [TEST] %-50s ... " "$test_name"
    if "$@"; then
        printf "\033[32mPASS\033[0m\n"
    else
        printf "\033[31mFAIL\033[0m\n"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

echo "=================================================="
echo " Running Shell Script Unit & Integration Tests   "
echo "=================================================="

# 1. Syntax check on all shell scripts
test_syntax() {
    bash -n "$REPO_ROOT/build.sh" && \
    bash -n "$REPO_ROOT/kernel-get.sh" && \
    bash -n "$REPO_ROOT/kernel-patch.sh" && \
    bash -n "$REPO_ROOT/mac-configure.sh" && \
    bash -n "$REPO_ROOT/tests/test_scripts.sh"
}
run_test "Bash Syntax Validation (bash -n)" test_syntax

# 2. Test mac-configure.sh --help
test_configure_help() {
    local output
    output=$("$REPO_ROOT/mac-configure.sh" --help 2>&1)
    [[ "$output" =~ "Usage:" ]] && [[ "$output" =~ "--dry-run" ]]
}
run_test "mac-configure.sh --help output" test_configure_help

# 3. Test mac-configure.sh --dry-run
test_configure_dry_run() {
    local output
    output=$("$REPO_ROOT/mac-configure.sh" --dry-run 2>&1)
    [[ "$output" =~ "Toolchain Verification Diagnostics" ]] && \
    [[ "$output" =~ "CONFIGURATION COMPLETE" ]]
}
run_test "mac-configure.sh --dry-run diagnostics" test_configure_dry_run

# 4. Test kernel-get.sh --help
test_kernel_get_help() {
    local output
    output=$("$REPO_ROOT/kernel-get.sh" --help 2>&1)
    [[ "$output" =~ "Usage:" ]] && [[ "$output" =~ "--type" ]] && [[ "$output" =~ "--version" ]]
}
run_test "kernel-get.sh --help output" test_kernel_get_help

# 5. Test kernel-get.sh custom version resolution and dry run download
test_kernel_get_resolution() {
    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/kg_test_XXXXXX")
    # Test specific version download with --no-extract
    if "$REPO_ROOT/kernel-get.sh" -v 6.1.100 --no-extract -o "$tmp_dir" >/dev/null 2>&1; then
        local archive_exists=false
        if [ -f "$tmp_dir/linux-6.1.100.tar.xz" ] || [ -f "$tmp_dir/linux-6.1.100.tar.gz" ]; then
            archive_exists=true
        fi
        rm -rf "$tmp_dir"
        $archive_exists
    else
        rm -rf "$tmp_dir"
        return 1
    fi
}
run_test "kernel-get.sh -v version resolution & download" test_kernel_get_resolution

# 6. Test kernel-get.sh longterm series resolution
test_kernel_get_longterm() {
    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/kg_lt_test_XXXXXX")
    if "$REPO_ROOT/kernel-get.sh" -t longterm -M 6 -m 12 --no-extract -o "$tmp_dir" >/dev/null 2>&1; then
        local count
        count=$(find "$tmp_dir" -name "linux-6.12.*" | wc -l)
        rm -rf "$tmp_dir"
        [ "$count" -ge 1 ]
    else
        rm -rf "$tmp_dir"
        return 1
    fi
}
run_test "kernel-get.sh -t longterm series resolution" test_kernel_get_longterm

# 7. Test build.sh --help
test_build_help() {
    local output
    output=$("$REPO_ROOT/build.sh" --help 2>&1)
    [[ "$output" =~ "Usage:" ]] && [[ "$output" =~ "--arch" ]] && [[ "$output" =~ "--cores" ]]
}
run_test "build.sh --help output" test_build_help

# 8. Test kernel-patch.sh on mock kernel directory
test_kernel_patch() {
    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/kp_test_XXXXXX")
    mkdir -p "$tmp_dir/scripts" "$tmp_dir/arch/arm64/tools"
    touch "$tmp_dir/Makefile"
    echo "kbuild-file = \$(or \$(wildcard \$(src)/Kbuild),\$(src)/Makefile)" > "$tmp_dir/scripts/Kbuild.include"
    echo 'sed "s/.*HWCAP\([0-9]*\)_\([A-Z0-9_]\+\).*/#define KERNEL_HWCAP_\2\t__khwcap\1_feature(\2)/"' > "$tmp_dir/arch/arm64/tools/gen-kernel-hwcaps.sh"
    
    "$REPO_ROOT/kernel-patch.sh" "$tmp_dir" >/dev/null 2>&1
    
    local patched_kbuild=false
    local patched_hwcaps=false
    if grep -q "Kbuild/." "$tmp_dir/scripts/Kbuild.include"; then
        patched_kbuild=true
    fi
    if ! grep -q '\\+' "$tmp_dir/arch/arm64/tools/gen-kernel-hwcaps.sh"; then
        patched_hwcaps=true
    fi
    rm -rf "$tmp_dir"
    $patched_kbuild && $patched_hwcaps
}
run_test "kernel-patch.sh mock kernel patching" test_kernel_patch

# 9. Test host-include directory structure
test_host_include_structure() {
    [ -f "$REPO_ROOT/host-include/host_fix.h" ] && \
    [ -f "$REPO_ROOT/host-include/elf.h" ] && \
    [ -f "$REPO_ROOT/host-include/byteswap.h" ] && \
    [ -f "$REPO_ROOT/host-include/endian.h" ] && \
    [ -f "$REPO_ROOT/host-include/asm/byteorder.h" ] && \
    [ -f "$REPO_ROOT/host-include/asm/types.h" ] && \
    [ -f "$REPO_ROOT/host-include/asm/posix_types.h" ]
}
run_test "host-include directory files existence" test_host_include_structure

echo "--------------------------------------------------"
echo "Tests Passed: $((TOTAL_TESTS - FAILED_TESTS))/$TOTAL_TESTS"

if [ $FAILED_TESTS -gt 0 ]; then
    echo "FAILED: $FAILED_TESTS test(s) failed."
    exit 1
else
    echo "SUCCESS: All script tests passed!"
    exit 0
fi
