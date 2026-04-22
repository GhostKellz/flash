# Releasing Flash

This is the release checklist used to keep Flash shippable.

## Versioning

1. update `build.zig.zon`
2. update `CHANGELOG.md`
3. confirm `src/root.zig` version test matches

## Verification

1. run `"/opt/zig-dev/zig" build`
2. run `"/opt/zig-dev/zig" build test --summary all`
3. run `docker compose run --rm flash-test /workspace/docker/scripts/full-check.sh`

## Documentation

1. verify README public surface claims are accurate
2. verify guides use current public API
3. verify examples are still copy-paste-safe
4. verify internal-only modules are not presented as stable

## Product Checks

1. Bash completion still works
2. Zsh completion generation still works
3. TOML via Flare is still the recommended config story
4. help/version/completion output still reflects the intended product positioning
