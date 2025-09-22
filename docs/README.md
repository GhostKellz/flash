# ⚡ Flash CLI Framework Documentation

Welcome to the comprehensive documentation for Flash, the lightning-fast CLI framework for Zig.

## 📚 Documentation Structure

### 🚀 [Getting Started](guides/getting-started.md)
- Installation and setup
- Your first Flash CLI
- Basic concepts and patterns

### 🏗️ [Architecture](architecture/)
- [CLI Structure](architecture/cli-structure.md) - Core architecture and design patterns
- [Async System](architecture/async-system.md) - Async/await and zsync integration
- [Memory Management](architecture/memory-management.md) - Zero-allocation patterns
- [Performance](architecture/performance.md) - Optimization strategies

### 📖 [API Documentation](api/)
- [CLI Module](api/cli.md) - Main CLI interface
- [Commands](api/commands.md) - Command definitions and handlers
- [Arguments & Flags](api/args-flags.md) - Input parsing and validation
- [Validation](api/validation.md) - Rich validation framework
- [Completion](api/completion.md) - Shell completion system
- [Testing](api/testing.md) - Testing utilities and infrastructure
- [Documentation](api/documentation.md) - Doc generation tools
- [Async Operations](api/async.md) - Async CLI capabilities
- [Benchmarking](api/benchmarking.md) - Performance testing

### 📝 [Guides](guides/)
- [Getting Started](guides/getting-started.md) - Quick start guide
- [Async CLI Development](guides/async-cli.md) - Building async CLI applications
- [Advanced Validation](guides/validation.md) - Custom validators and error handling
- [Shell Completions](guides/completions.md) - Setting up shell completions
- [Testing Your CLI](guides/testing.md) - Comprehensive testing strategies
- [Performance Optimization](guides/performance.md) - Making your CLI blazing fast
- [Migration Guide](guides/migration.md) - Migrating from other CLI frameworks

### 🎯 [Examples](examples/)
- [Basic CLI](examples/basic.md) - Simple command-line tool
- [Git-like Tool](examples/git-like.md) - Complex subcommand structure
- [File Processor](examples/file-processor.md) - Async file operations
- [API Client](examples/api-client.md) - Network operations and async
- [Build Tool](examples/build-tool.md) - Complex validation and configuration

### 🎓 [Tutorials](tutorials/)
- [Building a Package Manager](tutorials/package-manager.md) - Step-by-step guide
- [Creating a Development Server](tutorials/dev-server.md) - Async server with CLI
- [Log Analyzer](tutorials/log-analyzer.md) - File processing and reporting

## 🔗 Quick Links

- **[API Reference](api/)** - Complete API documentation
- **[Examples Repository](https://github.com/ghostkellz/flash-examples)** - Runnable examples
- **[Performance Benchmarks](https://github.com/ghostkellz/flash-benchmarks)** - Comparison with other frameworks
- **[Community Discord](https://discord.gg/flash-cli)** - Get help and share projects

## 🆚 Framework Comparison

| Feature | Flash | clap (Rust) | Cobra (Go) |
|---------|-------|-------------|------------|
| **Async Support** | ✅ Native | ❌ | ❌ |
| **Memory Safety** | ✅ Compile-time | ✅ Compile-time | ⚠️ Runtime |
| **Performance** | ⚡ Fastest | 🚀 Fast | 📈 Good |
| **Shell Completion** | ✅ All shells | ✅ All shells | ✅ All shells |
| **Rich Validation** | ✅ Advanced | ✅ Advanced | ✅ Good |
| **Testing Tools** | ✅ Complete | ✅ Complete | ✅ Good |
| **Doc Generation** | ✅ Multi-format | ✅ Man pages | ✅ Multiple |
| **Learning Curve** | 📚 Moderate | 📚 Moderate | 📖 Easy |

## 🤝 Contributing

- **[Contributing Guide](../CONTRIBUTING.md)** - How to contribute to Flash
- **[Architecture Decisions](architecture/decisions.md)** - Design rationale
- **[Roadmap](../ROADMAP.md)** - Future development plans

## 📄 License

Flash is dual-licensed under MIT and Apache 2.0. See [LICENSE](../LICENSE) for details.

---

*Built with ❤️ by the Flash community*