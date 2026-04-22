# Flash Documentation

Recommended evaluation path:

1. [Getting Started](guides/getting-started.md)
2. [Macro-First CLI](examples/macro-first.md)
3. [Flash + Flare](guides/flash-flare.md)
4. [Shell Completions](guides/completions.md)
5. [API Overview](api/README.md)
6. [Docker Verification](guides/docker-verification.md)

## Documentation Map

### Guides

- [Getting Started](guides/getting-started.md)
- [Declarative Config](guides/declarative-config.md)
- [Flash + Flare](guides/flash-flare.md)
- [Shell Completions](guides/completions.md)
- [Docker Verification](guides/docker-verification.md)
- [Async CLI Internals](guides/async-cli.md)

### API

- [API Overview](api/README.md)
- [CLI Module](api/cli.md)

### Examples

- [Basic CLI](examples/basic.md)
- [Macro-First CLI](examples/macro-first.md)

### Architecture

- [CLI Structure](architecture/cli-structure.md)
- [Async System](architecture/async-system.md)

## Support Expectations

- Core CLI construction is the recommended public path.
- Bash and Zsh are the strongest completion targets.
- TOML via Flare is the preferred config format.
- Internal async/security internals are not public API.

## Support Matrix

| Area | Status | Notes |
|------|--------|-------|
| Zig baseline | Supported | Zig `0.17.0-dev` |
| Linux | Verified | Local, Docker, Valgrind |
| Bash/Zsh | First-class | Best completion targets |
| Fish | Supported | Recursive generation |
| PowerShell/NuShell | Supported | Recursive generation |
| Core CLI API | Stable | Main recommended path |
| Declarative API | Experimental | Use explicit argv slices |
| Internal async/security modules | Internal-only | Not public API |
