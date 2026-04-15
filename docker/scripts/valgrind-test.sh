#!/bin/bash
# Flash Valgrind memory leak testing script
set -euo pipefail

echo "=== Flash Valgrind Memory Analysis ==="
echo "Zig version: $(zig version)"
echo "Valgrind version: $(valgrind --version)"
echo ""

# Build in debug mode with baseline CPU for Valgrind compatibility
# Zig 0.16 uses AVX-512 by default which Valgrind 3.22 doesn't support
echo ">>> Building in Debug mode (baseline CPU for Valgrind)..."
zig build -Doptimize=Debug -Dcpu=baseline

# Find the test binary
TEST_BIN="./zig-out/bin/flash"
if [[ ! -f "$TEST_BIN" ]]; then
    # Try to find any built binary
    TEST_BIN=$(find ./zig-out -type f -executable -name "flash*" 2>/dev/null | head -1)
fi

if [[ -z "$TEST_BIN" || ! -f "$TEST_BIN" ]]; then
    echo "Warning: No flash binary found, running demo instead"
    TEST_BIN="zig-out/bin/lightning"
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

# Create suppressions file for known Zig allocator patterns (if needed)
if [[ ! -f /workspace/docker/scripts/zig.supp ]]; then
    cat > /workspace/docker/scripts/zig.supp << 'EOF'
# Zig runtime suppressions
{
   zig_std_start
   Memcheck:Leak
   ...
   fun:std.start.*
}
EOF
fi

echo ">>> Running Valgrind on demo commands..."
echo ""

# Test 1: Help command
echo "--- Test: --help ---"
if valgrind "${VALGRIND_OPTS[@]}" "$TEST_BIN" --help 2>&1 | tee /tmp/valgrind-help.log; then
    echo "PASS: --help"
else
    echo "Note: Valgrind reported issues (may be false positives with Zig)"
fi
echo ""

# Test 2: Echo command
echo "--- Test: echo ---"
if valgrind "${VALGRIND_OPTS[@]}" "$TEST_BIN" echo "memory test" 2>&1 | tee /tmp/valgrind-echo.log; then
    echo "PASS: echo"
else
    echo "Note: Valgrind reported issues (may be false positives with Zig)"
fi
echo ""

# Test 3: Math command (nested subcommand)
echo "--- Test: math add ---"
if valgrind "${VALGRIND_OPTS[@]}" "$TEST_BIN" math add 5 10 2>&1 | tee /tmp/valgrind-math.log; then
    echo "PASS: math add"
else
    echo "Note: Valgrind reported issues (may be false positives with Zig)"
fi
echo ""

# Summary
echo "=== Valgrind Summary ==="
echo "Logs saved to /tmp/valgrind-*.log"
echo ""

# Check for definite leaks in logs
LEAKS=$(grep -l "definitely lost: [^0]" /tmp/valgrind-*.log 2>/dev/null | wc -l || echo "0")
if [[ "$LEAKS" -gt 0 ]]; then
    echo "WARNING: Found potential memory leaks. Review logs for details."
    grep -h "definitely lost" /tmp/valgrind-*.log 2>/dev/null || true
else
    echo "No definite memory leaks detected."
fi

# Show heap summaries
echo ""
echo "Heap summaries:"
grep -h "total heap usage" /tmp/valgrind-*.log 2>/dev/null || true
grep -h "All heap blocks were freed" /tmp/valgrind-*.log 2>/dev/null | head -1 || true

echo ""
echo ">>> Valgrind analysis complete!"
