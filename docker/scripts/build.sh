#!/bin/bash
# Flash build script for Docker container
set -euo pipefail

echo "=== Flash Build ==="
echo "Zig version: $(zig version)"
echo "Working directory: $(pwd)"
echo ""

echo ">>> Running zig build..."
zig build

echo ""
echo ">>> Build successful!"
