# Basic Flash Examples

Simple examples demonstrating core Flash features.

## hello.zig

Basic CLI with a greeting command.

**Features:**
- Simple command with handler
- String arguments with defaults
- Boolean and integer flags
- Basic output

**Usage:**
```bash
hello greet Alice
hello greet Bob --loud
hello greet World --count 3
hello greet Alice -l -c 5
```

## Building

```bash
zig build-exe hello.zig --dep flash -Mroot=hello.zig
./hello greet YourName
```

⚡ Built with Zig
