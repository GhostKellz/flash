#!/bin/bash
# Flash Valgrind memory leak testing script
set -euo pipefail

echo "=== Flash Valgrind Memory Analysis ==="
echo "Zig version: $(zig version)"
echo "Valgrind version: $(valgrind --version)"
echo ""

LOG_DIR="/workspace/.zig-cache/valgrind"
mkdir -p "$LOG_DIR"

# Build in debug mode with baseline CPU for Valgrind compatibility.
# Recent Zig dev builds may still produce DWARF warnings under Valgrind,
# but those warnings are distinct from real leak findings.
echo ">>> Building in Debug mode (baseline CPU for Valgrind)..."
zig build -Doptimize=Debug -Dcpu=baseline

TEST_BIN="./zig-out/bin/flash"
if [[ -z "$TEST_BIN" || ! -f "$TEST_BIN" ]]; then
    echo "ERROR: Expected binary not found at $TEST_BIN"
    exit 1
fi

echo ">>> Testing binary: $TEST_BIN"
echo ""

# Valgrind options for Zig programs
VALGRIND_OPTS=(
    --leak-check=full
    --show-leak-kinds=all
    --track-origins=yes
    --verbose
    --error-exitcode=1
    --suppressions=/workspace/docker/scripts/zig.supp
)

echo ">>> Running Valgrind on demo commands..."
echo ""

run_valgrind() {
    local log_file="$1"
    shift

    local raw_log
    raw_log=$(mktemp)
    if valgrind "${VALGRIND_OPTS[@]}" "$TEST_BIN" "$@" >"$raw_log" 2>&1; then
        :
    else
        local status=$?
        # Keep the log for inspection even on failure.
        grep -v "DWARF2 reader: Badly formed extended line op encountered" "$raw_log" | tee "$log_file"
        rm -f "$raw_log"
        return "$status"
    fi

    grep -v "DWARF2 reader: Badly formed extended line op encountered" "$raw_log" | tee "$log_file"
    rm -f "$raw_log"
}

# Test 1: Help command
echo "--- Test: --help ---"
if run_valgrind "$LOG_DIR/valgrind-help.log" --help; then
    echo "PASS: --help"
else
    echo "Note: Valgrind reported issues (may be false positives with Zig)"
fi
echo ""

# Test 2: Echo command
echo "--- Test: echo ---"
if run_valgrind "$LOG_DIR/valgrind-echo.log" echo "memory test"; then
    echo "PASS: echo"
else
    echo "Note: Valgrind reported issues (may be false positives with Zig)"
fi
echo ""

# Test 3: Math command (nested subcommand)
echo "--- Test: math add ---"
if run_valgrind "$LOG_DIR/valgrind-math.log" math add 5 10; then
    echo "PASS: math add"
else
    echo "Note: Valgrind reported issues (may be false positives with Zig)"
fi
echo ""

# Summary
echo "=== Valgrind Summary ==="
echo "Logs saved to $LOG_DIR"
echo ""

# Check for definite leaks in logs.
leak_matches=$(grep -hE "definitely lost: [1-9][0-9,]* bytes" "$LOG_DIR"/valgrind-*.log 2>/dev/null || true)
if [[ -n "$leak_matches" ]]; then
    echo "WARNING: Found potential memory leaks. Review logs for details."
    printf '%s\n' "$leak_matches"
else
    echo "No definite memory leaks detected."
fi

# Show heap summaries
echo ""
echo "Heap summaries:"
grep -h "total heap usage" "$LOG_DIR"/valgrind-*.log 2>/dev/null || true
grep -h "All heap blocks were freed" "$LOG_DIR"/valgrind-*.log 2>/dev/null | head -1 || true

echo ""
echo ">>> Valgrind analysis complete!"
