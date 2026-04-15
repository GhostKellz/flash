#!/bin/bash
# Flash test script for Docker container
set -euo pipefail

echo "=== Flash Test Suite ==="
echo "Zig version: $(zig version)"
echo ""

echo ">>> Running zig build test..."
zig build test

echo ""
echo ">>> Running demo commands..."
echo ""

echo "$ zig build run -- --help"
zig build run -- --help
echo ""

echo "$ zig build run -- echo 'Hello from Docker'"
zig build run -- echo "Hello from Docker"
echo ""

echo "$ zig build run -- math add 10 20"
zig build run -- math add 10 20
echo ""

echo ">>> All tests passed!"
