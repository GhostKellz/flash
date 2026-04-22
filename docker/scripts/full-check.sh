#!/bin/bash
# Flash complete verification script
set -euo pipefail

echo "========================================"
echo "  Flash CLI Framework - Full Check"
echo "========================================"
echo ""

# Format check
echo ">>> Step 1: Format check..."
if zig fmt --check src/*.zig; then
    echo "PASS: Code formatting OK"
else
    echo "WARN: Some files need formatting (run: zig fmt src/)"
fi
echo ""

# Build
echo ">>> Step 2: Build..."
/workspace/docker/scripts/build.sh
echo ""

# Tests
echo ">>> Step 3: Test suite..."
/workspace/docker/scripts/test.sh
echo ""

# Examples
echo ">>> Step 4: Example builds..."
zig build examples
echo "PASS: Shipped examples build"
echo ""

# Valgrind (optional, may have false positives)
echo ">>> Step 5: Memory analysis (Valgrind)..."
if /workspace/docker/scripts/valgrind-test.sh; then
    echo "PASS: Valgrind analysis completed"
else
    echo "WARN: Valgrind reported issues; inspect logs under /workspace/.zig-cache/valgrind"
fi
echo ""

echo "========================================"
echo "  Full Check Complete"
echo "========================================"
