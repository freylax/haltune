# Stack Research

**Domain:** LinuxCNC HAL Management Tool in Zig
**Researched:** 2026-01-28
**Confidence:** MEDIUM

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Zig** | 0.15.2 (stable) | Core language | Latest stable release (October 2025), proven stability for production use. 0.16.0-dev in active development but not stable yet. Pin to 0.15.2 to avoid breaking changes. |
| **Vaxis (libvaxis)** | latest (uses Zig 0.15.1) | TUI framework | Modern, actively maintained TUI library. Does not use terminfo (uses terminal queries). Provides both low-level API and high-level vxfw framework. Battle-tested with real applications. |
| **LinuxCNC HAL** | 2.9.7-9+ / 2.10 | Target system API | Documented APIs as of October 2025 (V2.9.7). 2.10 master branch available but 2.9.7 is stable. Use halcmd and HAL C library API via FFI. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **zig-clap** (Hejsil/zig-clap) | latest | CLI argument parsing | When you need elegant, streaming API for argument parsing. State machine-based, simpler alternatives available. |
| **yazap** (prajwalch/yazap) | latest | CLI argument parsing | When you need comprehensive CLI features inspired by Rust's clap (subcommands, validation). More feature-rich than zig-clap. |
| **Zig stdlib** | built-in | Testing, FFI, allocations | Always use. Use `zig test` for testing, `@cImport` for C headers, Arena allocators for TUI frame allocations. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **zig build** | Build system | Use instead of Make/CMake. Programmatic control over compilation, linking, and testing. Build via `build.zig` and dependencies via `build.zig.zon`. |
| **zig cc** | C compiler | Use for compiling any C code or testing FFI bindings. |
| **halcmd** | LinuxCNC HAL interaction | Command-line tool for manipulating HAL. Can read commands from files. Source reference available on GitHub. |

## Installation

### Core Dependencies

```bash
# Add Vaxis to your project
zig fetch --save git+https://github.com/rockorager/libvaxis.git

# Add CLI parsing library (choose one)
zig fetch --save git+https://github.com/Hejsil/zig-clap.git
# OR
zig fetch --save git+https://github.com/prajwalch/yazap.git
```

### build.zig Configuration

```zig
// In your build.zig
const vaxis = b.dependency("vaxis", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("vaxis", vaxis.module("vaxis"));

// For ZLS support
const exe_mod = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});
exe_mod.addImport("vaxis", vaxis.module("vaxis"));
```

### LinuxCNC Development Setup

```bash
# On Debian/Ubuntu systems with LinuxCNC installed
sudo apt-get install linuxcnc-uspace-dev liblinuxcnc-dev

# For compiling HAL components (if needed)
halcompile --install <component.c>
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Vaxis | TUI.zig (muhammad-fiaz) | If you need 36+ pre-built widgets and a more batteries-included approach. However, Vaxis has more active development and better terminal query support. |
| Vaxis vxfw (high-level) | Vaxis low-level API | If you need fine-grained control over every cell or custom event loop. Vxfw provides Flutter-like widget system, better for rapid development. |
| zig-clap / yazap | Stdlib-only parsing | If you want zero external dependencies. However, building robust CLI parsing from scratch is error-prone and the libraries are mature. |
| Zig 0.15.2 | Zig 0.16.0-dev | Only if you need bleeding-edge features and can accept instability. 0.16.0 is in active development with breaking changes. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **terminfo-based TUI libraries** | Vaxis doesn't use terminfo, uses terminal queries instead for better feature detection. Relying on terminfo can cause compatibility issues. | Vaxis with its built-in terminal query system |
| **Make / CMake** | Zig's build system (`zig build`) is more powerful and idiomatic. Mixing build systems creates complexity. | `zig build` with build.zig |
| **Unpinned Zig versions** | Zig is pre-1.0 with breaking changes between versions (especially 0.15.x). Using unpinned versions leads to breakage. | Pin to 0.15.2 explicitly in your environment |
| **Raw `@cInclude` without abstraction** | Direct `@cInclude` for entire LinuxCNC HAL headers creates maintenance burden. API changes can break builds. | Create idiomatic Zig wrapper layer around HAL C API |
| **Async/await (coming back)** | Async/await was removed from Zig and is being redesigned. Using it now is premature. | Use the provided Vaxis event loop (thread-safe, separate thread for TTY reading) |

## Stack Patterns by Variant

**If building for Raspberry Pi 5:**
- Use `zig build -Dtarget=aarch64-linux-gnu` for cross-compilation
- Consider using `-Doptimize=ReleaseFast` for performance on embedded hardware
- Test with LinuxCNC 2.9 ARM packages

**If building for x86_64 dev machine:**
- Use native target: `zig build`
- Use `-Doptimize=Debug` for development, can use `-fincremental` flag for faster iteration
- Test against both LinuxCNC 2.9 and 2.10 if possible

**If targeting riocore framework environments:**
- Detect riocore presence by checking for `riocore/files/riocomp.c` in LinuxCNC config
- Look for generated HAL files in `Output/BOARD_NAME/LinuxCNC/` directory structure
- Support both standalone and riocore-integrated modes

**If needing offline operation:**
- Cache dependencies in project directory
- LinuxCNC HAL headers are typically installed in `/usr/include/linuxcnc/` or similar
- Consider bundling generated HAL bindings for offline builds

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Vaxis | Zig 0.15.1+ | Vaxis explicitly uses Zig 0.15.1. Should work with 0.15.2 (same minor version). |
| LinuxCNC 2.9.7 | Debian Trixie / Bookworm | Current stable release as of October 2025. Well-documented API. |
| LinuxCNC 2.10 | Master branch | In development. API should be stable but use with caution. |
| zig-clap | Zig 0.13+ | No explicit minimum version stated, but actively maintained. |
| yazap | Zig 0.13+ | Inspired by clap-rs, modern Zig idioms. |

**Critical compatibility note:** Zig 0.15 introduced massive breaking changes to the standard library (defaulting to unmanaged lists, IO changes). Ensure all dependencies are compatible with 0.15.x specifically, not just "latest Zig."

## FFI Patterns for LinuxCNC HAL

### Recommended Approach

1. **Use `@cImport` for HAL headers:**
   ```zig
   const hal = @cImport(@cInclude("hal.h"));
   ```

2. **Create idiomatic Zig wrappers:**
   - Wrap C structs with Zig equivalents where possible
   - Use Zig error sets instead of C error codes
   - Leverage Zig's `extern` structs for C ABI compatibility

3. **Memory management:**
   - Use Arena allocators for temporary allocations
   - Be explicit about ownership (C allocations vs Zig allocations)
   - Use `defer` for cleanup guarantees

4. **HAL interaction patterns:**
   - Use `halcmd` via process spawning for high-level operations
   - Use HAL C API directly for real-time operations (pins, signals, parameters)
   - Consider creating a HAL component in Zig compiled as a C library for advanced use cases

### Example: HAL Pin Reading

```zig
const std = @import("std");
const hal = @cImport(@cInclude("hal.h"));

pub fn readPin(pin_name: []const u8) !f64 {
    // Implementation would call hal functions
    // Return Zig error type on failure
}
```

## Build System Recommendations

### Use `zig build` Exclusively

**Why:**
- Programmatic control (Zig code, not config file syntax)
- Seamless cross-compilation
- Built-in test runner
- Dependency management via `build.zig.zon`

**Best Practices:**
- Define build steps for: development, release, test, docs
- Use `b.addExecutable()` for main binary
- Use `b.addTest()` for test targets
- Use `b.addModule()` for library code organization

### Dependency Management

**Current state (2025):**
- `zig fetch` for adding dependencies
- `build.zig.zon` for dependency metadata
- Transitive dependency fetching is still being improved (GitHub issue #20976)
- Git fetch can have issues with some servers (GitLab, etc.)

**Recommendations:**
- Pin specific commits in `build.zig.zon`
- Test dependency fetching in sandboxed builds
- Consider vendoring critical dependencies if needed for offline operation

## Testing Strategy

### Use Built-in `zig test`

- No external test frameworks needed
- Use `test` blocks directly in source files
- Run all tests with `zig build test`
- Use snapshot testing for TUI rendering verification
  - Reference: [Dead Simple Snapshot Testing In Zig](https://kristoff.it/blog/dead-simple-snapshot-testing/)

### Test Organization

```
src/
  main.zig
  hal/
    pin.zig
    signal.zig
    pin_test.zig
    signal_test.zig
  tui/
    app.zig
    app_test.zig
```

### Integration Testing

For LinuxCNC integration:
- Use `halcmd` in test fixtures to set up HAL state
- Test against mock HAL API when LinuxCNC not available
- Consider integration tests that run against real LinuxCNC instance in CI

## Riocore Framework Integration

### Detection Pattern

```zig
const std = @import("std");

pub fn detectRiocore(allocator: std.mem.Allocator) !bool {
    // Check for riocore-generated files
    const paths = [_][]const u8{
        "/usr/lib/linuxcnc/riocomp.c",
        "Output/*/LinuxCNC/rio.ini",
    };

    for (paths) |path| {
        if (std.fs.cwd().openFile(path, .{})) |file| {
            file.close();
            return true;
        } else |_| {}
    }

    return false;
}
```

### Why This Matters

Riocore is a code generator for FPGA-based real-time I/O:
- Generates HAL/INI files from JSON configuration
- Common in cost-sensitive LinuxCNC setups
- Detecting riocore presence enables context-aware UI
- Not present in all LinuxCNC installations (must support both cases)

## Performance Considerations for Raspberry Pi 5

### Optimization Levels

- **Development:** `-Doptimize=Debug`
- **Testing:** `-Doptimize=ReleaseSafe` (checks enabled)
- **Production:** `-Doptimize=ReleaseFast` (best performance)

### Memory Usage

- Vaxis uses double-buffering for screen rendering
- Arena allocators reduce fragmentation in TUI loop
- Be mindful of per-frame allocations (use ctx.arena in vxfw)

### TTY Performance

- Use buffered writers for terminal output
- Vaxis provides optimized rendering (only updates changed cells)
- Consider reducing refresh rate for complex TUIs on slower hardware

## Sources

### Zig Language
- [Zig 0.15.2 Release](https://ziglang.org/documentation/0.15.2/) - Latest stable release documentation (HIGH confidence)
- [Zig 0.15.1 Release Notes](https://ziglang.org/download/0.15.1/release-notes.html) - Release details and breaking changes (HIGH confidence)
- [A Practical Introduction to Zig's Build System](https://dev.to/hexshift/understanding-buildzig-a-practical-introduction-to-zigs-build-system-6gh) - May 2025 (MEDIUM confidence)
- [Using Zig's Build System for C Projects in 2025](https://alwint3r.medium.com/using-zigs-build-system-for-c-projects-in-2025-e451ba9bfc46) - June 2025 (MEDIUM confidence)
- [Best Practices for Structuring Zig Projects with External Dependencies](https://ziggit.dev/t/best-practices-for-structuring-zig-projects-with-external-dependencies/3723) - March 2024 (MEDIUM confidence)

### Vaxis TUI Framework
- [GitHub: rockorager/libvaxis](https://github.com/rockorager/libvaxis) - Official repository (HIGH confidence)
- Repository explicitly states "Vaxis uses zig 0.15.1" (HIGH confidence)
- Documentation shows both low-level and vxfw high-level APIs (HIGH confidence)
- Does not use terminfo, uses terminal queries (HIGH confidence)

### LinuxCNC HAL
- [LinuxCNC Developer Manual V2.9.7](http://linuxcnc.org/docs/2.9/pdf/LinuxCNC_Developer_nb.pdf) - October 22, 2025 (HIGH confidence)
- [HALCMD Manual Page](https://linuxcnc.org/docs/html/man/man1/halcmd.1.html) - Official documentation (HIGH confidence)
- [HAL Tutorial](http://linuxcnc.org/docs/html/hal/tutorial.html) - HAL usage patterns (HIGH confidence)
- [HAL Tools Documentation](https://linuxcnc.org/docs/html/hal/tools.html) - December 15, 2025 (HIGH confidence)
- [GitHub: LinuxCNC linuxcnc/src/hal/utils/halcmd.c](https://github.com/LinuxCNC/linuxcnc/blob/master/src/hal/utils/halcmd.c) - Source reference (HIGH confidence)

### Zig FFI Patterns
- [How Zig Lets You Gradually Migrate or Mix C Code Safely](https://marsmatics.com/how-zig-lets-you-gradually-migrate-or-mix-c-code-safely/) - June 2025 (MEDIUM confidence)
- [Zig; what I think after months of using it](https://strongly-typed-thoughts.net/blog/zig-2025) - February 2025 (MEDIUM confidence)
- [ramonmeza/zig-c-tutorial](https://github.com/ramonmeza/zig-c-tutorial) - C interop tutorial (MEDIUM confidence)

### CLI Argument Parsing
- [GitHub: prajwalch/yazap](https://github.com/prajwalch/yazap) - CLI parsing library (MEDIUM confidence)
- [GitHub: Hejsil/zig-clap](https://github.com/Hejsil/zig-clap) - CLI parsing library (MEDIUM confidence)
- [Zig Cookbook - Argument Parsing](https://cookbook.ziglang.cc/13-01-argparse/) - Comparison of options (MEDIUM confidence)

### Testing
- [Dead Simple Snapshot Testing In Zig](https://kristoff.it/blog/dead-simple-snapshot-testing/) - February 9, 2025 (MEDIUM confidence)

### Dependency Management
- [Build.zig.zon: 'raw' dependencies are fetched on each build](https://ziggit.dev/t/build-zig-zon-raw-dependencies-are-fetched-on-each-build/8915) - March 2025 (MEDIUM confidence)
- [Adding dependencies to your Zig project with zig fetch](https://www.bradcypert.com/adding-dependencies-to-your-zig-project-with-zig-fetch/) - (MEDIUM confidence)
- [GitHub Issue #20976: zig build --fetch transitive dependencies](https://github.com/ziglang/zig/issues/20976) - August 2024 (MEDIUM confidence)

### Riocore Framework
- [GitHub: multigcs/riocore](https://github.com/multigcs/riocore) - Official repository (HIGH confidence)
- [Riocore setup from scratch for dummies](https://forum.linuxcnc.org/9-installing-linuxcnc/53710-riocore-setup-from-scratch-for-dummies) - September 2024 (MEDIUM confidence)

---
*Stack research for: LinuxCNC HAL Management Tool in Zig*
*Researched: 2026-01-28*
