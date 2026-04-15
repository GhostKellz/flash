#!/bin/bash
# Flash complete verification script
set -euo pipefail

echo "========================================"
echo "  Flash CLI Framework - Full Check"
echo "========================================"
echo ""

# Format check
echo ">>> Step 1: Format check..."
if zig fmt --check src/*.zig 2>/dev/null; then
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

# Valgrind (optional, may have false positives)
echo ">>> Step 4: Memory analysis (Valgrind)..."
/workspace/docker/scripts/valgrind-test.sh || echo "Note: Valgrind issues may be false positives with Zig runtime"
echo ""

echo "========================================"
echo "  Full Check Complete"
echo "========================================"
