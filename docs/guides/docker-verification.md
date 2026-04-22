# Docker Verification Environment

Flash includes a Docker-based verification environment for consistent testing and memory leak detection with Valgrind.

The container verification flow is intended as a release-readiness check, not a production image workflow.

## Quick Start

```bash
# Build and run tests
docker compose run --rm flash-test /workspace/docker/scripts/full-check.sh

# Or run individual checks
docker compose run --rm flash-test /workspace/docker/scripts/build.sh
docker compose run --rm flash-test /workspace/docker/scripts/test.sh
docker compose run --rm flash-test /workspace/docker/scripts/valgrind-test.sh
```

## Setup

The environment uses:
- **Alpine Linux** - Minimal container image
- **Host networking** - Avoids DNS resolution issues
- **Valgrind** - Memory leak detection
- **Mounted Zig** - Uses host's Zig installation

### docker-compose.yml

```yaml
services:
  flash-test:
    build:
      context: .
      dockerfile: docker/Dockerfile
      network: host
    network_mode: host
    volumes:
      - .:/workspace:rw
      - /opt/zig-dev:/opt/zig:ro
    working_dir: /workspace
```

### docker/Dockerfile

```dockerfile
FROM alpine:3.19
RUN apk add --no-cache bash coreutils valgrind git curl musl-dev
RUN adduser -D -h /home/flash flash
WORKDIR /workspace
ENV PATH="/opt/zig:${PATH}"
USER flash
CMD ["/bin/bash"]
```

## Scripts

### docker/scripts/build.sh

Builds the project in multiple optimization modes:
- Debug (default)
- ReleaseSafe
- ReleaseFast

### docker/scripts/test.sh

Runs the full test suite:
```bash
zig build test --summary all
```

### docker/scripts/valgrind-test.sh

Runs memory leak analysis on demo commands:

```bash
# Build with baseline CPU for Valgrind compatibility
zig build -Doptimize=Debug -Dcpu=baseline

# Run Valgrind on key commands
valgrind --leak-check=full ./zig-out/bin/flash --help
valgrind --leak-check=full ./zig-out/bin/flash echo "test"
valgrind --leak-check=full ./zig-out/bin/flash math add 5 10
```

### docker/scripts/full-check.sh

Complete verification pipeline:
1. Format check (`zig fmt --check`)
2. Build
3. Test suite
4. Valgrind memory analysis

## Valgrind Notes

### AVX-512 Compatibility

Current Zig `0.17.0-dev` builds may use instructions that Valgrind 3.22 does not fully support. The `-Dcpu=baseline` flag forces a more compatible instruction set:

```bash
zig build -Doptimize=Debug -Dcpu=baseline
```

### Suppressions

A suppressions file at `docker/scripts/zig.supp` handles known Zig runtime patterns:

```
{
   zig_std_start
   Memcheck:Leak
   ...
   fun:std.start.*
}
```

### Interpreting Results

```
HEAP SUMMARY:
    in use at exit: 0 bytes in 0 blocks
  total heap usage: X allocs, X frees, Y bytes allocated

All heap blocks were freed -- no leaks are possible
```

Zero "definitely lost" bytes indicates no memory leaks.

Valgrind may still print DWARF reader warnings with Zig dev builds. Treat those as tooling/debug-info noise unless they are accompanied by non-zero leak summaries or a non-zero Valgrind exit status.

## Host Networking

The environment uses `network_mode: host` because:
- Docker bridge networking has DNS resolution issues on some systems
- NFTables configuration can interfere with container networking
- Host networking provides direct access to system resources

## Running Locally Without Docker

```bash
# Format check
zig fmt --check src/*.zig

# Build
zig build

# Test
zig build test

# Valgrind (requires baseline CPU)
zig build -Doptimize=Debug -Dcpu=baseline
valgrind --leak-check=full ./zig-out/bin/flash --help
```

## Troubleshooting

### "SIGILL" from Valgrind

Add `-Dcpu=baseline` to the build command.

### DNS resolution errors

Ensure `network_mode: host` is set in docker-compose.yml.

### Permission denied

Check that scripts are executable:
```bash
chmod +x docker/scripts/*.sh
```
