# 📚 Flash API Documentation

Complete API reference for the Flash CLI framework.

## 📖 Core Modules

### [CLI Module](cli.md)
Main interface for creating and running CLI applications.

```zig
const cli = flash.CLI(.{
    .name = "myapp",
    .version = "1.0.0",
    .commands = &.{...},
});
```

### [Commands](commands.md)
Command definitions, handlers, and subcommand hierarchies.

```zig
flash.cmd("deploy", .{
    .about = "Deploy application",
    .run_async = deployHandler,
    .commands = &.{...},
})
```

### [Arguments & Flags](args-flags.md)
Input parsing, validation, and type-safe access.

```zig
flash.arg("file", .{
    .help = "Input file",
    .required = true,
    .validator = fileValidator,
})
```

### [Context](context.md)
Execution context and parameter access.

```zig
fn handler(ctx: flash.Context) !void {
    const file = ctx.get("file").?;
    const verbose = ctx.getBool("verbose");
}
```

## 🔧 Advanced Features

### [Validation](validation.md)
Rich validation framework with custom validators.

```zig
const validator = flash.validation.portInRange(1024, 65535);
const email_validator = flash.validation.emailValidator();
```

### [Completion](completion.md)
Shell completion generation system.

```zig
var generator = flash.completion.CompletionGenerator.init(allocator);
const script = try generator.generate(command, .bash, "myapp");
```

### [Testing](testing.md)
Comprehensive testing utilities and infrastructure.

```zig
var harness = flash.testing.TestHarness.init(allocator);
const result = try harness.execute(cli, &.{"command", "arg"});
```

### [Documentation](documentation.md)
Multi-format documentation generation.

```zig
var doc_gen = flash.documentation.DocGenerator.init(allocator, config);
const markdown = try doc_gen.generate(command, .markdown, "myapp");
```

### [Async Operations](async.md)
Async CLI capabilities and concurrent operations.

```zig
var async_ctx = flash.async_cli.AsyncContext.init(allocator);
const results = try async_ctx.executeParallel(commands);
```

### [Benchmarking](benchmarking.md)
Performance testing and metrics collection.

```zig
var benchmark = flash.benchmark.BenchmarkRunner.init(allocator, config);
const result = try benchmark.benchmark("test", function, args);
```

## 🎯 Quick Reference

### Common Types

```zig
// Main types
flash.CLI(config)           // CLI application type
flash.Context              // Execution context
flash.Command              // Command definition
flash.Argument             // Argument specification
flash.Flag                 // Flag specification

// Error types
flash.Error.FlashError     // Main error union
flash.Error.ValidationError // Validation failures
flash.Error.ParseError     // Parsing failures

// Async types
flash.async_cli.AsyncContext      // Async execution context
flash.async_cli.AsyncCommand      // Async command specification
flash.async_cli.AsyncResult       // Async operation result

// Testing types
flash.testing.TestHarness         // CLI testing harness
flash.testing.TestResult          // Test execution result
flash.testing.SnapshotTester      // Snapshot testing utility

// Validation types
flash.validation.ValidationResult  // Validation outcome
flash.validation.ValidatorFn       // Validator function type
flash.validation.ValidationChain   // Multiple validators

// Completion types
flash.completion.Shell             // Target shell enum
flash.completion.CompletionGenerator // Completion script generator
```

### Builder Functions

```zig
// CLI building
flash.CLI(config)          // Create CLI type
flash.cmd(name, config)    // Define command
flash.arg(name, config)    // Define argument
flash.flag(name, config)   // Define flag

// Validation
flash.validation.emailValidator()
flash.validation.portInRange(min, max)
flash.validation.fileValidator(must_exist, extensions)
flash.validation.choiceValidator(choices, case_sensitive)

// Async operations
flash.async_cli.AsyncContext.init(allocator)
flash.async_cli.AsyncFileOps.init(allocator)
flash.async_cli.AsyncNetOps.init(allocator)

// Testing
flash.testing.TestHarness.init(allocator)
flash.testing.SnapshotTester.init(allocator, dir, update)
flash.testing.PerformanceTester.init(allocator)

// Documentation
flash.documentation.DocGenerator.init(allocator, config)
```

### Configuration Enums

```zig
// Shell types for completion
.bash, .zsh, .fish, .powershell, .nushell

// Documentation formats
.markdown, .html, .man, .json, .yaml

// Validation directives
.default, .no_space, .no_file_comp, .filter_file_ext

// Error kinds
.invalid_type, .out_of_range, .invalid_format, .missing_required

// Async result types
.success, .error, .timeout, .cancelled
```

## 💡 Usage Patterns

### Basic CLI
```zig
const MyCLI = flash.CLI(.{
    .name = "myapp",
    .version = "1.0.0",
    .about = "My CLI application",
    .commands = &.{
        flash.cmd("greet", .{
            .about = "Greet someone",
            .args = &.{
                flash.arg("name", .{.required = true}),
            },
            .run = greetHandler,
        }),
    },
});

fn greetHandler(ctx: flash.Context) !void {
    const name = ctx.get("name").?;
    std.debug.print("Hello, {s}!\n", .{name});
}
```

### Async CLI
```zig
async fn asyncHandler(ctx: flash.Context) !void {
    const files = ctx.getMany("files").?;

    var file_ops = flash.async_cli.AsyncFileOps.init(ctx.allocator);
    defer file_ops.deinit();

    const results = try file_ops.readFiles(files);
    // Process results...
}
```

### With Validation
```zig
flash.arg("port", .{
    .help = "Port number",
    .required = true,
    .validator = flash.validation.portInRange(1024, 65535),
})
```

### With Testing
```zig
test "command execution" {
    var harness = flash.testing.TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const result = try harness.execute(MyCLI, &.{"greet", "World"});
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("Hello, World!");
}
```

## 🔗 Related Documentation

- [Getting Started Guide](../guides/getting-started.md)
- [Architecture Overview](../architecture/cli-structure.md)
- [Async Development Guide](../guides/async-cli.md)
- [Examples](../examples/)
- [Tutorials](../tutorials/)

---

*Complete API documentation for building lightning-fast CLI applications with Flash.*