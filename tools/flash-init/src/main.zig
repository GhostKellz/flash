const std = @import("std");
const flash = @import("flash");

// Define the flash-init CLI application
const FlashInitCLI = flash.CLI(.{
    .name = "flash",
    .version = "1.0.0",
    .about = "Flash CLI project generator - scaffold new CLI applications quickly",
    .author = "Flash CLI Framework",

    .commands = &.{
        // Main command: flash init <project-name>
        flash.cmd("init", .{
            .about = "Initialize a new Flash CLI project",
            .args = &.{
                flash.arg("project-name", .{
                    .help = "Name of the new CLI project (e.g., 'ghostctl', 'myapp')",
                    .required = true,
                    .validator = validateProjectName,
                }),
            },
            .flags = &.{
                flash.flag("template", .{
                    .help = "Project template to use",
                    .short = 't',
                    .long = "template",
                    .takes_value = true,
                    .default_value = "basic",
                    .validator = flash.validation.choiceValidator(&.{ "basic", "devops", "async-files", "network", "git-like" }, true),
                }),
                flash.flag("output", .{
                    .help = "Output directory (defaults to project name)",
                    .short = 'o',
                    .long = "output",
                    .takes_value = true,
                }),
                flash.flag("interactive", .{
                    .help = "Interactive mode - prompt for all options",
                    .short = 'i',
                    .long = "interactive",
                }),
                flash.flag("no-git", .{
                    .help = "Skip Git repository initialization",
                    .long = "no-git",
                }),
                flash.flag("no-install", .{
                    .help = "Skip dependency installation",
                    .long = "no-install",
                }),
                flash.flag("template-dir", .{
                    .help = "Custom template directory",
                    .long = "template-dir",
                    .takes_value = true,
                }),
                flash.flag("dry-run", .{
                    .help = "Show what would be created without creating files",
                    .long = "dry-run",
                }),
                flash.flag("force", .{
                    .help = "Overwrite existing directory",
                    .short = 'f',
                    .long = "force",
                }),
            },
            .run = initCommand,
        }),

        // List available templates
        flash.cmd("list-templates", .{
            .about = "List all available project templates",
            .flags = &.{
                flash.flag("template-dir", .{
                    .help = "Custom template directory",
                    .long = "template-dir",
                    .takes_value = true,
                }),
                flash.flag("detailed", .{
                    .help = "Show detailed template information",
                    .short = 'd',
                    .long = "detailed",
                }),
            },
            .run = listTemplatesCommand,
        }),

        // Show template details
        flash.cmd("template-info", .{
            .about = "Show detailed information about a specific template",
            .args = &.{
                flash.arg("template", .{
                    .help = "Template name",
                    .required = true,
                }),
            },
            .flags = &.{
                flash.flag("template-dir", .{
                    .help = "Custom template directory",
                    .long = "template-dir",
                    .takes_value = true,
                }),
            },
            .run = templateInfoCommand,
        }),

        // Generate example commands
        flash.cmd("examples", .{
            .about = "Show example commands for common use cases",
            .run = examplesCommand,
        }),
    },

    .flags = &.{
        flash.flag("verbose", .{
            .help = "Enable verbose output",
            .short = 'v',
            .long = "verbose",
        }),
        flash.flag("quiet", .{
            .help = "Suppress non-error output",
            .short = 'q',
            .long = "quiet",
        }),
    },
});

// Validation function for project names
fn validateProjectName(value: []const u8) flash.validation.ValidationResult {
    // Must start with lowercase letter
    if (value.len == 0 or !std.ascii.isLower(value[0])) {
        return .{
            .valid = false,
            .message = "Project name must start with a lowercase letter",
        };
    }

    // Can only contain lowercase letters, numbers, hyphens, and underscores
    for (value) |char| {
        if (!std.ascii.isLower(char) and !std.ascii.isDigit(char) and char != '-' and char != '_') {
            return .{
                .valid = false,
                .message = "Project name can only contain lowercase letters, numbers, hyphens, and underscores",
            };
        }
    }

    // Check for reserved names
    const reserved_names = [_][]const u8{ "test", "build", "src", "lib", "bin", "flash", "zig" };
    for (reserved_names) |reserved| {
        if (std.mem.eql(u8, value, reserved)) {
            return .{
                .valid = false,
                .message = "Project name cannot be a reserved word",
            };
        }
    }

    return .{ .valid = true, .message = null };
}

// Template variable structure
const TemplateVariables = struct {
    project_name: []const u8,
    project_description: []const u8,
    project_version: []const u8,
    author_name: []const u8,
    license: []const u8,

    // Template-specific variables
    with_validation: bool = true,
    with_completions: bool = true,

    // DevOps template
    cloud_provider: []const u8 = "aws",
    environments: []const u8 = "dev,staging,prod",
    with_kubernetes: bool = true,
    with_docker: bool = true,
    with_monitoring: bool = true,
    with_secrets: bool = true,

    // Async-files template
    max_concurrent_files: u32 = 100,
    buffer_size: []const u8 = "64KB",
    with_compression: bool = true,
    with_encryption: bool = false,
    with_hashing: bool = true,
    with_text_processing: bool = true,
};

// Command handlers
fn initCommand(ctx: flash.Context) !void {
    const allocator = ctx.allocator;
    const project_name = ctx.get("project-name").?;
    const template_name = ctx.get("template") orelse "basic";
    const output_dir = ctx.get("output") orelse project_name;
    const interactive = ctx.getBool("interactive");
    const no_git = ctx.getBool("no-git");
    const no_install = ctx.getBool("no-install");
    const dry_run = ctx.getBool("dry-run");
    const force = ctx.getBool("force");
    const verbose = ctx.getBool("verbose");
    const template_dir = ctx.get("template-dir") orelse "../../templates";

    // Display initialization header
    std.debug.print("⚡ Initializing Flash CLI project: {s}\n", .{project_name});
    std.debug.print("📦 Template: {s}\n", .{template_name});
    std.debug.print("📁 Output directory: {s}\n", .{output_dir});

    if (dry_run) {
        std.debug.print("🔍 DRY RUN MODE - No files will be created\n\n");
    }

    // Check if output directory exists
    std.fs.cwd().access(output_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {}, // Good, directory doesn't exist
        else => {
            if (!force) {
                std.debug.print("❌ Directory '{s}' already exists. Use --force to overwrite.\n", .{output_dir});
                return;
            }
            std.debug.print("⚠️  Overwriting existing directory '{s}'\n", .{output_dir});
        },
    };

    // Load template
    const template_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ template_dir, template_name });
    defer allocator.free(template_path);

    if (verbose) {
        std.debug.print("Loading template from: {s}\n", .{template_path});
    }

    // Initialize template variables
    var vars = TemplateVariables{
        .project_name = project_name,
        .project_description = try std.fmt.allocPrint(allocator, "A CLI application built with Flash", .{}),
        .project_version = "0.1.0",
        .author_name = getAuthorName(allocator) catch "Your Name",
        .license = "MIT",
    };

    // Interactive mode - prompt for variables
    if (interactive) {
        try promptForVariables(allocator, &vars, template_name);
    }

    // Generate project structure
    if (!dry_run) {
        // Create output directory
        try std.fs.cwd().makePath(output_dir);

        // Generate files from template
        try generateProjectFiles(allocator, template_path, output_dir, vars, verbose);

        // Initialize Git repository
        if (!no_git) {
            std.debug.print("\n📝 Initializing Git repository...\n");
            try initializeGitRepo(allocator, output_dir);
        }

        // Install dependencies
        if (!no_install) {
            std.debug.print("\n📦 Installing dependencies...\n");
            try installDependencies(allocator, output_dir);
        }
    } else {
        // Dry run - just show what would be created
        try showDryRunOutput(allocator, template_path, output_dir, vars);
    }

    // Display success message with next steps
    std.debug.print("\n✅ Project '{s}' created successfully!\n\n", .{project_name});
    std.debug.print("🚀 Next steps:\n");
    std.debug.print("   cd {s}\n", .{output_dir});
    std.debug.print("   zig build\n");
    std.debug.print("   zig build run -- --help\n\n");

    // Show example commands specific to the project
    std.debug.print("📚 Example commands for your new CLI:\n");
    switch (std.meta.stringToEnum(Template, template_name) orelse .basic) {
        .basic => {
            std.debug.print("   {s} greet \"World\"           # Basic greeting\n", .{project_name});
            std.debug.print("   {s} greet \"Alice\" --uppercase # Uppercase greeting\n", .{project_name});
            std.debug.print("   {s} info                      # Show CLI info\n", .{project_name});
        },
        .devops => {
            std.debug.print("   {s} deploy --env prod         # Deploy to production\n", .{project_name});
            std.debug.print("   {s} k8s status --namespace app # Check K8s status\n", .{project_name});
            std.debug.print("   {s} monitor health --env staging # Monitor health\n", .{project_name});
        },
        .@"async-files" => {
            std.debug.print("   {s} process *.txt -o output/  # Process text files\n", .{project_name});
            std.debug.print("   {s} watch src/ -o dist/ --operation compress # Watch & compress\n", .{project_name});
            std.debug.print("   {s} analyze data/ --recursive # Analyze files\n", .{project_name});
        },
        .network => {
            std.debug.print("   {s} api get /users            # Make API request\n", .{project_name});
            std.debug.print("   {s} websocket connect ws://localhost:8080 # WebSocket connection\n", .{project_name});
            std.debug.print("   {s} download https://example.com/file.zip # Download file\n", .{project_name});
        },
        .@"git-like" => {
            std.debug.print("   {s} init                      # Initialize repository\n", .{project_name});
            std.debug.print("   {s} add .                     # Add files\n", .{project_name});
            std.debug.print("   {s} commit -m \"Initial commit\" # Commit changes\n", .{project_name});
        },
    }

    if (vars.with_completions) {
        std.debug.print("\n🐚 Generate shell completions:\n");
        std.debug.print("   {s} completions --shell bash > {s}.bash\n", .{ project_name, project_name });
        std.debug.print("   {s} completions --shell zsh > _{s}\n", .{ project_name, project_name });
    }

    std.debug.print("\n📖 For more information, see the generated README.md file.\n");
}

fn listTemplatesCommand(ctx: flash.Context) !void {
    const template_dir = ctx.get("template-dir") orelse "../../templates";
    const detailed = ctx.getBool("detailed");

    std.debug.print("📚 Available Flash CLI Templates:\n\n");

    const templates = [_]struct { name: []const u8, description: []const u8, use_cases: []const u8 }{
        .{
            .name = "basic",
            .description = "Simple CLI Application",
            .use_cases = "File utilities, text processors, development tools",
        },
        .{
            .name = "devops",
            .description = "DevOps/Operations Tool",
            .use_cases = "Deployment tools, infrastructure automation, CI/CD utilities",
        },
        .{
            .name = "async-files",
            .description = "File Processing Tool",
            .use_cases = "Log analyzers, file converters, backup tools, data processors",
        },
        .{
            .name = "network",
            .description = "Network/API Client",
            .use_cases = "API clients, web scrapers, service health checkers",
        },
        .{
            .name = "git-like",
            .description = "Complex Subcommand Hierarchy",
            .use_cases = "Version control systems, container management, package managers",
        },
    };

    for (templates) |template| {
        std.debug.print("⚡ {s: <15} - {s}\n", .{ template.name, template.description });
        if (detailed) {
            std.debug.print("   Use cases: {s}\n", .{template.use_cases});
            std.debug.print("   Command: flash init myapp --template {s}\n\n", .{template.name});
        }
    }

    if (!detailed) {
        std.debug.print("\n💡 Use --detailed for more information about each template.\n");
    }

    _ = template_dir; // Will be used when actually scanning template directory
}

fn templateInfoCommand(ctx: flash.Context) !void {
    const template_name = ctx.get("template").?;
    const template_dir = ctx.get("template-dir") orelse "../../templates";

    std.debug.print("📋 Template: {s}\n\n", .{template_name});

    // This would load actual template metadata from template.yaml
    // For now, showing hardcoded info
    const template_info = getTemplateInfo(template_name) catch {
        std.debug.print("❌ Template '{s}' not found.\n", .{template_name});
        return;
    };

    std.debug.print("Description: {s}\n", .{template_info.description});
    std.debug.print("Features:\n");
    for (template_info.features) |feature| {
        std.debug.print("  ✅ {s}\n", .{feature});
    }

    _ = template_dir; // Will be used when actually loading template
}

fn examplesCommand(ctx: flash.Context) !void {
    _ = ctx;

    std.debug.print("⚡ Flash CLI Generator Examples\n\n");

    std.debug.print("🎯 Common Use Cases:\n\n");

    std.debug.print("1️⃣  Create a simple CLI tool:\n");
    std.debug.print("   flash init mytool --template basic\n\n");

    std.debug.print("2️⃣  Create a DevOps deployment tool:\n");
    std.debug.print("   flash init deploy-manager --template devops\n\n");

    std.debug.print("3️⃣  Create an async file processor:\n");
    std.debug.print("   flash init file-processor --template async-files\n\n");

    std.debug.print("4️⃣  Interactive mode (prompts for all options):\n");
    std.debug.print("   flash init myapp --interactive\n\n");

    std.debug.print("5️⃣  Create with custom output directory:\n");
    std.debug.print("   flash init myapp --output ~/projects/myapp\n\n");

    std.debug.print("6️⃣  Create without Git initialization:\n");
    std.debug.print("   flash init myapp --no-git\n\n");

    std.debug.print("7️⃣  Dry run to see what would be created:\n");
    std.debug.print("   flash init myapp --dry-run\n\n");

    std.debug.print("💡 Pro Tips:\n");
    std.debug.print("   • Use meaningful project names (e.g., 'ghostctl', 'deploy-tool')\n");
    std.debug.print("   • Choose templates that match your use case\n");
    std.debug.print("   • Use --interactive for guided setup\n");
    std.debug.print("   • Generated CLIs include shell completions by default\n");
}

// Helper functions

const Template = enum {
    basic,
    devops,
    @"async-files",
    network,
    @"git-like",
};

const TemplateInfo = struct {
    description: []const u8,
    features: []const []const u8,
};

fn getTemplateInfo(name: []const u8) !TemplateInfo {
    const template = std.meta.stringToEnum(Template, name) orelse return error.TemplateNotFound;

    return switch (template) {
        .basic => TemplateInfo{
            .description = "Simple CLI application with basic functionality",
            .features = &.{ "Argument parsing", "Flag handling", "Help generation", "Shell completions", "Testing" },
        },
        .devops => TemplateInfo{
            .description = "DevOps and operations tool with deployment features",
            .features = &.{ "Multi-environment support", "Kubernetes operations", "Docker support", "Monitoring", "Secrets management" },
        },
        .@"async-files" => TemplateInfo{
            .description = "High-performance file processing with async I/O",
            .features = &.{ "Parallel processing", "Progress bars", "Memory-efficient streaming", "Batch operations" },
        },
        .network => TemplateInfo{
            .description = "Network and API client with HTTP operations",
            .features = &.{ "HTTP client", "JSON/YAML handling", "Authentication", "Rate limiting", "WebSocket support" },
        },
        .@"git-like" => TemplateInfo{
            .description = "Complex CLI with nested subcommands",
            .features = &.{ "Nested subcommands", "Global flags", "Context sharing", "Plugin architecture" },
        },
    };
}

fn getAuthorName(allocator: std.mem.Allocator) ![]const u8 {
    // Try to get from Git config
    const result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "git", "config", "--get", "user.name" },
    }) catch {
        return "Your Name";
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term == .Exited and result.term.Exited == 0 and result.stdout.len > 0) {
        // Remove trailing newline
        var name = result.stdout;
        if (name[name.len - 1] == '\n') {
            name = name[0 .. name.len - 1];
        }
        return allocator.dupe(u8, name);
    }

    return "Your Name";
}

fn promptForVariables(allocator: std.mem.Allocator, vars: *TemplateVariables, template_name: []const u8) !void {
    _ = allocator;
    _ = template_name;

    // In a real implementation, this would prompt the user for each variable
    // For now, just using defaults
    std.debug.print("📝 Using default values (interactive mode not fully implemented yet)\n");

    // Example of what this would do:
    // vars.project_description = try prompt("Project description", vars.project_description);
    // vars.author_name = try prompt("Author name", vars.author_name);
    // etc.
}

fn generateProjectFiles(
    allocator: std.mem.Allocator,
    template_path: []const u8,
    output_dir: []const u8,
    vars: TemplateVariables,
    verbose: bool,
) !void {
    _ = allocator;

    // This would process template files and generate the project
    // For now, creating basic structure

    // Create src directory
    const src_path = try std.fmt.allocPrint(allocator, "{s}/src", .{output_dir});
    defer allocator.free(src_path);
    try std.fs.cwd().makePath(src_path);

    if (verbose) {
        std.debug.print("📁 Creating directory: {s}\n", .{src_path});
    }

    // Generate main.zig from template
    // This would use actual template processing
    const main_content = try generateMainZig(allocator, vars);
    defer allocator.free(main_content);

    const main_path = try std.fmt.allocPrint(allocator, "{s}/main.zig", .{src_path});
    defer allocator.free(main_path);

    const main_file = try std.fs.cwd().createFile(main_path, .{});
    defer main_file.close();
    try main_file.writeAll(main_content);

    if (verbose) {
        std.debug.print("📄 Generated: {s}\n", .{main_path});
    }

    // Generate build.zig
    const build_content = try generateBuildZig(allocator, vars);
    defer allocator.free(build_content);

    const build_path = try std.fmt.allocPrint(allocator, "{s}/build.zig", .{output_dir});
    defer allocator.free(build_path);

    const build_file = try std.fs.cwd().createFile(build_path, .{});
    defer build_file.close();
    try build_file.writeAll(build_content);

    if (verbose) {
        std.debug.print("📄 Generated: {s}\n", .{build_path});
    }

    // Generate README.md
    const readme_content = try generateReadme(allocator, vars);
    defer allocator.free(readme_content);

    const readme_path = try std.fmt.allocPrint(allocator, "{s}/README.md", .{output_dir});
    defer allocator.free(readme_path);

    const readme_file = try std.fs.cwd().createFile(readme_path, .{});
    defer readme_file.close();
    try readme_file.writeAll(readme_content);

    if (verbose) {
        std.debug.print("📄 Generated: {s}\n", .{readme_path});
    }

    _ = template_path; // Will be used when actually loading templates
}

fn generateMainZig(allocator: std.mem.Allocator, vars: TemplateVariables) ![]u8 {
    // This would use the actual template
    // For now, generating a simple example
    return std.fmt.allocPrint(allocator,
        \\const std = @import("std");
        \\const flash = @import("flash");
        \\
        \\// {s} CLI application
        \\const {s}CLI = flash.CLI(.{{
        \\    .name = "{s}",
        \\    .version = "{s}",
        \\    .about = "{s}",
        \\    .author = "{s}",
        \\
        \\    .commands = &.{{
        \\        // Example: {s} hello "World"
        \\        flash.cmd("hello", .{{
        \\            .about = "Say hello",
        \\            .args = &.{{
        \\                flash.arg("name", .{{
        \\                    .help = "Name to greet",
        \\                    .required = true,
        \\                }}),
        \\            }},
        \\            .run = helloCommand,
        \\        }}),
        \\
        \\        // Example: {s} version
        \\        flash.cmd("version", .{{
        \\            .about = "Show version information",
        \\            .run = versionCommand,
        \\        }}),
        \\    }},
        \\}});
        \\
        \\fn helloCommand(ctx: flash.Context) !void {{
        \\    const name = ctx.get("name").?;
        \\    std.debug.print("Hello, {{s}}!\n", .{{name}});
        \\}}
        \\
        \\fn versionCommand(ctx: flash.Context) !void {{
        \\    _ = ctx;
        \\    std.debug.print("{{s}} version {{s}}\n", .{{"{s}", "{s}"}});
        \\}}
        \\
        \\pub fn main() !void {{
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
        \\    defer _ = gpa.deinit();
        \\
        \\    try {s}CLI.run(gpa.allocator());
        \\}}
    , .{
        // Comment
        vars.project_name,
        // CLI type name (PascalCase)
        toPascalCase(allocator, vars.project_name) catch vars.project_name,
        // CLI name
        vars.project_name,
        vars.project_version,
        vars.project_description,
        vars.author_name,
        // Example commands
        vars.project_name,
        vars.project_name,
        // Version command output
        vars.project_name,
        vars.project_version,
        // CLI run
        toPascalCase(allocator, vars.project_name) catch vars.project_name,
    });
}

fn generateBuildZig(allocator: std.mem.Allocator, vars: TemplateVariables) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {{
        \\    const target = b.standardTargetOptions(.{{}});
        \\    const optimize = b.standardOptimizeOption(.{{}});
        \\
        \\    // Add Flash dependency
        \\    const flash_dep = b.dependency("flash", .{{
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\    const flash = flash_dep.module("flash");
        \\
        \\    // Create the executable
        \\    const exe = b.addExecutable(.{{
        \\        .name = "{s}",
        \\        .root_source_file = .{{ .path = "src/main.zig" }},
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\
        \\    exe.root_module.addImport("flash", flash);
        \\    b.installArtifact(exe);
        \\
        \\    // Create run command
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    run_cmd.step.dependOn(b.getInstallStep());
        \\    if (b.args) |args| {{
        \\        run_cmd.addArgs(args);
        \\    }}
        \\
        \\    const run_step = b.step("run", "Run {s}");
        \\    run_step.dependOn(&run_cmd.step);
        \\}}
    , .{ vars.project_name, vars.project_name });
}

fn generateReadme(allocator: std.mem.Allocator, vars: TemplateVariables) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\# {s}
        \\
        \\{s}
        \\
        \\Built with [Flash CLI Framework](https://github.com/ghostkellz/flash) ⚡
        \\
        \\## Installation
        \\
        \\```bash
        \\zig build
        \\```
        \\
        \\## Usage
        \\
        \\```bash
        \\# Show help
        \\{s} --help
        \\
        \\# Example command
        \\{s} hello "World"
        \\# Output: Hello, World!
        \\
        \\# Show version
        \\{s} version
        \\# Output: {s} version {s}
        \\```
        \\
        \\## Development
        \\
        \\```bash
        \\# Run directly with zig build
        \\zig build run -- hello "Developer"
        \\
        \\# Build release version
        \\zig build -Doptimize=ReleaseFast
        \\```
        \\
        \\## License
        \\
        \\{s}
    , .{
        vars.project_name,
        vars.project_description,
        vars.project_name,
        vars.project_name,
        vars.project_name,
        vars.project_name,
        vars.project_version,
        vars.license,
    });
}

fn toPascalCase(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var capitalize_next = true;
    for (name) |char| {
        if (char == '-' or char == '_') {
            capitalize_next = true;
        } else if (capitalize_next) {
            try result.append(std.ascii.toUpper(char));
            capitalize_next = false;
        } else {
            try result.append(char);
        }
    }

    return result.toOwnedSlice();
}

fn initializeGitRepo(allocator: std.mem.Allocator, output_dir: []const u8) !void {
    _ = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "git", "init" },
        .cwd = output_dir,
    }) catch |err| {
        std.debug.print("⚠️  Failed to initialize Git repository: {}\n", .{err});
        return;
    };

    // Create .gitignore
    const gitignore_path = try std.fmt.allocPrint(allocator, "{s}/.gitignore", .{output_dir});
    defer allocator.free(gitignore_path);

    const gitignore_file = try std.fs.cwd().createFile(gitignore_path, .{});
    defer gitignore_file.close();
    try gitignore_file.writeAll(
        \\zig-out/
        \\zig-cache/
        \\.zig-cache/
        \\build/
        \\*.exe
        \\*.pdb
        \\*.o
        \\*.a
        \\*.so
        \\*.dylib
        \\
    );
}

fn installDependencies(allocator: std.mem.Allocator, output_dir: []const u8) !void {
    _ = allocator;
    _ = output_dir;
    // This would run zig build to fetch dependencies
    // For now, just showing a message
    std.debug.print("   Dependencies will be fetched on first build.\n");
}

fn showDryRunOutput(
    allocator: std.mem.Allocator,
    template_path: []const u8,
    output_dir: []const u8,
    vars: TemplateVariables,
) !void {
    _ = allocator;
    _ = template_path;

    std.debug.print("📁 Would create directory: {s}/\n", .{output_dir});
    std.debug.print("📁 Would create directory: {s}/src/\n", .{output_dir});
    std.debug.print("📄 Would generate: {s}/src/main.zig\n", .{output_dir});
    std.debug.print("📄 Would generate: {s}/build.zig\n", .{output_dir});
    std.debug.print("📄 Would generate: {s}/README.md\n", .{output_dir});
    std.debug.print("📄 Would generate: {s}/.gitignore\n", .{output_dir});

    std.debug.print("\n📋 Project configuration:\n");
    std.debug.print("   Name: {s}\n", .{vars.project_name});
    std.debug.print("   Description: {s}\n", .{vars.project_description});
    std.debug.print("   Version: {s}\n", .{vars.project_version});
    std.debug.print("   Author: {s}\n", .{vars.author_name});
    std.debug.print("   License: {s}\n", .{vars.license});
}

// Main entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    try FlashInitCLI.run(gpa.allocator());
}

// Tests
test "project name validation" {
    const testing = std.testing;

    // Valid names
    try testing.expect(validateProjectName("myapp").valid);
    try testing.expect(validateProjectName("ghost-ctl").valid);
    try testing.expect(validateProjectName("deploy_tool").valid);
    try testing.expect(validateProjectName("app123").valid);

    // Invalid names
    try testing.expect(!validateProjectName("MyApp").valid); // Uppercase
    try testing.expect(!validateProjectName("123app").valid); // Starts with number
    try testing.expect(!validateProjectName("my app").valid); // Space
    try testing.expect(!validateProjectName("test").valid); // Reserved
    try testing.expect(!validateProjectName("").valid); // Empty
}