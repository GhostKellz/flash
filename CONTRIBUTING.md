# Contributing

## Development Setup

This project currently targets Zig `0.17.0-dev`.

Recommended baseline:

```sh
zig version
zig build
zig build test
```

## Workflow

1. Create a focused branch.
2. Keep changes small and scoped.
3. Run formatting and verification before opening a PR.
4. Update docs when behavior or public APIs change.

## Code Guidelines

- Prefer small, direct changes over broad rewrites.
- Keep exported APIs internally consistent.
- Make incomplete features fail explicitly instead of pretending to succeed.
- Do not add new placeholders that silently return fake success values.
- Keep comments short and focused on why the code exists.

## Verification

Before submitting, run:

```sh
zig build
zig build test
```

If you touch formatting-sensitive files, also run:

```sh
zig fmt src/*.zig build.zig
```

## Documentation

- Keep long-form documentation under `docs/`.
- Keep task planning and review artifacts under `tasks/`.
- Update `README.md` when changing the public feature set.
- Do not market unfinished features as supported behavior.

## Pull Requests

Good PRs usually include:

- A clear problem statement
- A minimal fix or improvement
- Tests covering changed behavior
- Notes about risks, follow-ups, or limitations

## Security

If your change touches credentials, auth flows, process execution, or filesystem permissions, review `SECURITY.md` and treat those paths as high risk.

Do not open public issues for vulnerabilities.

## Areas That Need Help

- Parser correctness and nested command handling
- Help and completion generation
- Test harness realism and coverage
- Config parsing behavior
- Security hardening for credential storage and auth flows
