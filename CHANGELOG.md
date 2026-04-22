# Changelog

All notable changes to Flash will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-04-21

### Added
- Built-in `completion` and internal `__complete` command paths wired through the CLI runtime
- Real dynamic Bash completion context handling for nested subcommands and option-value completion
- Real async dynamic completion execution for `async_completion_fn`
- Recursive completion generation for Zsh, Fish, PowerShell, and NuShell command trees
- Shared command-scope/global-flag resolution used across parser defaults, runtime help, and completion generation
- End-to-end tests covering nested help routing, inherited global flags, dynamic completion context parsing, and recursive completion backends
- Golden snapshot coverage for help output, Bash completion, Zsh completion, and TOML diagnostics
- Checked-in snapshot fixtures under `tests/snapshots/`
- Public API/stability overview, installation guide, migration guide, and release checklist docs
- Production-grade example documentation and shipped source example
- `zig build verify` step covering build, tests, and shipped examples

### Changed
- Migrated TOML parsing from zontom to flare
- Updated to Zig 0.17.0-dev
- README badge updated to 0.17-dev
- Updated build/test coverage to run the full module suite by default
- Added Flare-backed TOML diagnostics and presence-aware config merge support
- Version metadata is now sourced from `build.zig.zon`
- README, guides, and examples were reworked around the macro-first product direction and the current completion/backend maturity
- Bash and Zsh completion are now the strongest supported backends; Fish is recursive/shared-scope; PowerShell and NuShell now emit recursive command trees
- Replaced the old `zsync` dependency with Flash-owned internal async foundations
- Internal async command execution, validation, completion, and tooling now run on Flash's owned thread-backed future runtime
- README and docs now include an explicit support matrix and clearer stable/experimental/internal boundaries
- Shipped examples were rewritten to the current public API and are now built as part of verification
- Docker full-check now includes shipped example builds in addition to build, tests, and Valgrind

### Fixed
- Version test updated to match package version
- Resolved remaining Zig 0.17 stdlib migration issues in parser, config, declarative, validation, testing, and related support modules
- Removed ad hoc `/tmp/flash*` test scratch usage and moved test scratch into project-local `.zig-cache/tmp`
- Fixed misleading `zig build test` warning-style output caused by progress rendering and noisy stderr during passing tests
- Fixed hidden/help/completion inconsistencies, option-style help rendering, and nested subcommand help targeting
- Fixed stale Zig `0.16` references in Docker/test artifacts and bundled templates
- Removed the remaining `zsync` imports from command, completion, validation, async, and benchmark codepaths
- Fixed the declarative public path to stop referencing removed Zig stdlib argv helpers on the current baseline
- Fixed snapshot tests to use repo-relative fixture paths so they pass in both local and Docker verification

---

## [0.3.6] - 2026-04-19

### Changed
- Removed zontom dependency (archived)
- Updated zsync to v0.8.0
- Updated to Zig 0.17.0-dev

---

## [0.3.5] - 2026-04-15

### Added
- Nested subcommand support with full command path tracking
- Context.getCommandPath() for accessing full command hierarchy
- Context.pushCommand() for building command paths
- TestHarness now performs real CLI execution with output capture
- MockCLI test helper with proper getRootCommand() interface
- Shell completion promoted to stable (Bash, Zsh, Fish, PowerShell, NuShell)
- ArgumentConfig.choices for enum-like constrained values
- ArgumentConfig.withChoices() builder method
- Argument.getChoices() and hasChoices() accessors
- Choice validation in Argument.parseValue() (returns InvalidChoice error)
- Help output displays available choices for constrained arguments
- Shell completion generators suggest choices for arguments (bash, zsh, fish)
- FieldConfig.validator and choices wired to ArgumentConfig in declarative.zig
- Tests for declarative validator wiring and choices wiring
- Tests for prompts module configuration builders
- promptForArgument now handles all ArgTypes including array and enum with choices
- TOML configuration parsing via Flare integration
- Tests for env.zig FileConfigNotSupported error and builder methods
- Tests for declarative hidden/multiple/short/long field wiring
- Tests for macro helpers (ChainBuilder, arg, flag, Middleware, withValidation)
- Consumer-level tests for generateCommand with full config
- Documentation: docs/guides/declarative-config.md
- Documentation: docs/guides/docker-verification.md
- InvalidChoice error type for choice validation failures
- Typed enum/choices example in README.md
- Documentation links section in README.md (declarative-config, docker-verification, completions, getting-started)

### Changed
- Version is now sourced from build.zig.zon at compile time via build options
- TOML config parsing now works via Flare; YAML returns `UnsupportedConfigFormat`
- README rebaselined with accurate feature maturity (stable/experimental/planned)
- Badges updated to for-the-badge style
- Testing infrastructure rewritten for real CLI execution (was fake mock output)
- CLI.findCommandByPath() now recursively resolves nested subcommands
- Demo main.zig simplified, async demonstrations removed
- FieldConfig.env removed from declarative.zig (use env.zig directly instead)

### Security
- Removed security module from public API pending safe implementation
- OAuth and credential storage features are not available in this release
- See tasks/code_review.md for details on identified vulnerabilities

### Fixed
- Version constant in root.zig now matches package version (was 0.1.0, now 0.3.5)
- Fixed API inconsistencies in completion.zig (flag.config.* access pattern)
- Fixed broken builder functions in macros.zig (removed nonexistent withName calls)
- Fixed declarative.zig env field reference (field does not exist on ArgumentConfig)
- Added buffer bounds check in demo echo command (max 256 characters for uppercase)
- Fixed broken path reference in templates/README.md
- Fixed positional argument parsing that was overwriting first arg in nested commands
- Fixed memory leak in Context.addArrayValue() (old array not freed on growth)
- Fixed memory leak in Context.deinit() (array values not freed)
- Fixed Context.debug() to use command_path instead of removed subcommand field
- Fixed TestHarness nested command resolution to walk full command path
- Fixed README.md minimal example to use current API (init with root config, runWithInit)
- Async module functions now return error.Unimplemented instead of fake success
- Security OAuth functions now return error.SecurityDisabled instead of placeholder tokens
- templates/README.md rewritten to be reference-only (no flash-init examples)
- Help.generateCompletion() now delegates to real CompletionGenerator (was TODO stub)
- Help.generateCompletionToWriter() added for writer-based completion output
- CLI.generateCompletion() now calls correct Help method
- completion.zig handleCompletionCommand() now uses typed context accessors (getString)
- prompts.zig promptForArgument() fixed to use std.fmt.allocPrint (was self.fmt)
- macros.zig parseCommandSpec() now parses command name, args, and description (was hardcoded stub)
- macros.zig CommandDef.build() now uses struct declarations for name/about (was using field names)
- Added end-to-end tests for completion generation through Help interface
- Added tests for completion.zig command execution helpers and file output
- declarative.zig getFieldConfig() now reads `fieldname_config` declarations from structs
- validators.zig regex() renamed to pattern() with alias, docs clarify it's preset-based not true regex
- env.zig LayeredConfig file source now returns explicit FileConfigNotSupported error
- config.zig template generation no longer emits TODO placeholders
- All experimental modules (Declarative, Macros, Prompts, Validators) have limitation docs
- root.zig exports have inline comments documenting experimental module limitations
- Added Docker-based verification environment (Alpine + Valgrind + host networking)
- Added docker/scripts/ for build, test, and memory leak verification
- docs/guides/async-cli.md updated to note async module is internal/future
- root.zig module doc now lists all shell completion targets (Bash, Zsh, Fish, PowerShell, NuShell)
- root.zig Prompts comment clarifies visible password input limitation
- declarative-config.md limitations section updated (env field removed, hidden/multiple now wired)
- README.md TOML feature now links to Flare

### Removed
- Removed `Async` export from public API (async.zig remains internal)
- Removed `Security` export from public API (security.zig remains internal)
- Removed tools/flash-init/ (stale API, pending rewrite for v0.4.x)
- Removed unused macro stubs: templateCommand, CommandHierarchy, Middleware.chain
- Removed stale documentation files (DOCS.md, INTEGRATION.md, TODO.md)
- Cleaned up .gitignore to exclude vgcore.* and local development artifacts

## [0.3.4] - Previous

- Version bump, Zig version update

## [0.3.3] and earlier

- Initial development releases
