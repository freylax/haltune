// .hal file parser for extracting HAL commands and origin tracking
//
// This module parses .hal configuration files to extract:
// - setp commands (parameter settings with line numbers)
// - net commands (signal connections with line numbers)
// - loadrt/loadusr commands (component loading)
// - addf commands (function additions)
// - Comments (lines starting with # or ;)
//
// The parser supports:
// - Line continuation with backslash (\)
// - Quoted strings (single and double quotes)
// - Arbitrary whitespace
// - Empty lines and comments

const std = @import("std");
const HalError = @import("../ffi/errors.zig").HalError;
const HalValue = @import("../state/cache.zig").HalValue;

/// HAL command types that can be parsed from .hal files
pub const HalCommand = union(enum) {
    /// setp pin/param-name value
    setp: struct {
        name: []const u8,
        value: HalValue,
        line: usize,
    },

    /// net signal-name pin1 [arrow] pin2...
    net: struct {
        signal_name: []const u8,
        pins: []const []const u8,
        line: usize,
    },

    /// loadrt component [options]
    loadrt: struct {
        component: []const u8,
        options: []const []const u8,
        line: usize,
    },

    /// loadusr component [options]
    loadusr: struct {
        component: []const u8,
        options: []const []const u8,
        line: usize,
    },

    /// addf function-name thread-name
    addf: struct {
        function_name: []const u8,
        thread_name: []const u8,
        line: usize,
    },

    /// unlinkp pin-name
    unlinkp: struct {
        pin_name: []const u8,
        line: usize,
    },

    /// start command (begin realtime execution)
    start: struct {
        line: usize,
    },

    /// Comment line (# or ; at start)
    comment: struct {
        text: []const u8,
        line: usize,
    },
};

/// Parse result containing all commands and metadata
pub const HalParseResult = struct {
    /// All parsed commands in file order
    commands: std.ArrayList(HalCommand),

    /// Original file path (for origin tracking)
    file_path: []const u8,

    /// Deinitialize and free all resources
    pub fn deinit(self: *HalParseResult) void {
        self.commands.deinit();
        self.* = undefined;
    }
};

/// Parse a .hal file and extract all commands with line numbers
///
/// This function reads the entire file, processes line continuations,
/// and parses each command into structured data.
///
/// Parameters:
///   - allocator: Memory allocator for all returned data
///   - file_path: Path to .hal file to parse
///   - content: Optional file content (if already loaded)
///
/// Returns:
///   - HalParseResult with all commands
///   - error.FileNotFound if file doesn't exist
///   - error.OutOfMemory if allocation fails
///
/// Thread safety:
///   - Not thread-safe (use separate parse per thread)
///
/// Example:
/// ```
/// const result = try parseHalFile(allocator, "custom.hal", null);
/// defer result.deinit();
///
/// for (result.commands.items) |cmd| {
///     switch (cmd) {
///         .setp => |s| std.debug.print("Line {}: setp {s} = {}\n", .{s.line, s.name, s.value}),
///         .net => |n| std.debug.print("Line {}: net {s}\n", .{n.line, n.signal_name}),
///         else => {},
///     }
/// }
/// ```
pub fn parseHalFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    content: ?[]const u8,
) !HalParseResult {
    var result = HalParseResult{
        .commands = std.ArrayList(HalCommand){},
        .file_path = try allocator.dupe(u8, file_path),
    };

    // Read file if content not provided
    const file_content = content orelse
        try std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024 * 10); // 10MB max
    defer if (content == null) allocator.free(file_content);

    // Process line continuations first
    const continued_lines = try processLineContinuations(allocator, file_content);
    defer {
        for (continued_lines.items) |line| {
            allocator.free(line);
        }
        continued_lines.deinit(allocator);
    }

    // Parse each line
    for (continued_lines.items, 0..) |line, line_num| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        // Skip empty lines
        if (trimmed.len == 0) continue;

        // Check for comment
        if (isComment(trimmed)) {
            try result.commands.append(allocator, .{
                .comment = .{
                    .text = try allocator.dupe(u8, trimmed),
                    .line = line_num + 1,
                },
            });
            continue;
        }

        // Parse command
        const cmd = try parseCommand(allocator, trimmed, line_num + 1);
        try result.commands.append(allocator, cmd);
    }

    return result;
}

/// Process line continuations (backslash at end of line)
///
/// Lines ending with backslash are continued on the next line.
/// The backslash and newline are removed, concatenating the lines.
fn processLineContinuations(
    allocator: std.mem.Allocator,
    content: []const u8,
) !std.ArrayList([]const u8) {
    var lines = std.ArrayList([]const u8){};
    var line_iter = std.mem.splitScalar(u8, content, '\n');

    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    while (line_iter.next()) |line| {
        // Trim trailing whitespace from line
        const trimmed_end = std.mem.trimRight(u8, line, &std.ascii.whitespace);

        if (trimmed_end.len > 0 and trimmed_end[trimmed_end.len - 1] == '\\') {
            // Line continuation - remove backslash and add to buffer
            try buffer.appendSlice(allocator, trimmed_end[0 .. trimmed_end.len - 1]);
        } else {
            // End of continuation - add full line
            try buffer.appendSlice(allocator, line);
            try lines.append(allocator, try buffer.toOwnedSlice());
            buffer.items.len = 0; // Clear buffer
        }
    }

    // Handle last line if it doesn't end with newline
    if (buffer.items.len > 0) {
        try lines.append(allocator, try buffer.toOwnedSlice());
    }

    return lines;
}

/// Check if a line is a comment
///
/// Comments start with # or ; at the beginning (ignoring leading whitespace)
fn isComment(line: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, line, &std.ascii.whitespace);
    return trimmed.len > 0 and (trimmed[0] == '#' or trimmed[0] == ';');
}

/// Parse a single HAL command line
///
/// Determines command type and parses arguments appropriately.
fn parseCommand(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_num: usize,
) !HalCommand {
    // Get first word to determine command type
    var iter = std.mem.tokenizeScalar(u8, line, ' ');
    const cmd_word = iter.next() orelse return error.InvalidCommand;

    // Lowercase for comparison
    const cmd_lower = toLower(allocator, cmd_word);
    defer allocator.free(cmd_lower);

    if (std.mem.eql(u8, cmd_lower, "setp")) {
        return try parseSetp(allocator, line, line_num);
    } else if (std.mem.eql(u8, cmd_lower, "net")) {
        return try parseNet(allocator, line, line_num);
    } else if (std.mem.eql(u8, cmd_lower, "loadrt")) {
        return try parseLoadrt(allocator, line, line_num);
    } else if (std.mem.eql(u8, cmd_lower, "loadusr")) {
        return try parseLoadusr(allocator, line, line_num);
    } else if (std.mem.eql(u8, cmd_lower, "addf")) {
        return try parseAddf(allocator, line, line_num);
    } else if (std.mem.eql(u8, cmd_lower, "unlinkp")) {
        return try parseUnlinkp(allocator, line, line_num);
    } else if (std.mem.eql(u8, cmd_lower, "start")) {
        return .{ .start = .{ .line = line_num } };
    }

    // Unknown command - treat as comment for now
    return .{
        .comment = .{
            .text = try allocator.dupe(u8, line),
            .line = line_num,
        },
    };
}

/// Parse setp command: setp pin/param-name value
///
/// Value parsing handles:
/// - Floating point: 1.5, -0.01, 1e-3
/// - Integers: 42, -10
/// - Bit (boolean): TRUE, FALSE, 1, 0 (case-insensitive)
fn parseSetp(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_num: usize,
) !HalCommand {
    var iter = std.mem.tokenizeScalar(u8, line, ' ');

    // Skip "setp"
    _ = iter.next();

    // Get pin/param name
    const name = iter.next() orelse return error.MissingArgument;
    const name_owned = try allocator.dupe(u8, name);

    // Get remaining text as value string
    const value_start = iter.index orelse return error.MissingArgument;

    // Extract value string (handling quotes)
    const value_str = std.mem.trim(u8, line[value_start..], &std.ascii.whitespace);

    // Parse value based on type
    const value = try parseHalValue(allocator, value_str);

    return .{
        .setp = .{
            .name = name_owned,
            .value = value,
            .line = line_num,
        },
    };
}

/// Parse net command: net signal-name pin1 [arrow] pin2...
///
/// Direction arrows (=>, <=, <=>) are preserved for readability
/// but are not semantically significant.
fn parseNet(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_num: usize,
) !HalCommand {
    var iter = std.mem.tokenizeAny(u8, line, " \t");

    // Skip "net"
    _ = iter.next();

    // Get signal name
    const signal_name = iter.next() orelse return error.MissingArgument;
    const signal_owned = try allocator.dupe(u8, signal_name);

    // Collect remaining tokens as pins
    var pins = std.ArrayList([]const u8){};

    while (iter.next()) |token| {
        // Skip direction arrows (they're cosmetic)
        if (std.mem.eql(u8, token, "=>") or
            std.mem.eql(u8, token, "<=") or
            std.mem.eql(u8, token, "<=>"))
        {
            continue;
        }

        // Store pin name
        try pins.append(allocator, try allocator.dupe(u8, token));
    }

    return .{
        .net = .{
            .signal_name = signal_owned,
            .pins = try pins.toOwnedSlice(),
            .line = line_num,
        },
    };
}

/// Parse loadrt command: loadrt component [options]
fn parseLoadrt(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_num: usize,
) !HalCommand {
    var iter = std.mem.tokenizeScalar(u8, line, ' ');

    // Skip "loadrt"
    _ = iter.next();

    // Get component name
    const component = iter.next() orelse return error.MissingArgument;
    const component_owned = try allocator.dupe(u8, component);

    // Collect options
    var options = std.ArrayList([]const u8){};
    while (iter.next()) |token| {
        try options.append(allocator, try allocator.dupe(u8, token));
    }

    return .{
        .loadrt = .{
            .component = component_owned,
            .options = try options.toOwnedSlice(),
            .line = line_num,
        },
    };
}

/// Parse loadusr command: loadusr component [options]
fn parseLoadusr(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_num: usize,
) !HalCommand {
    var iter = std.mem.tokenizeScalar(u8, line, ' ');

    // Skip "loadusr"
    _ = iter.next();

    // Get component name
    const component = iter.next() orelse return error.MissingArgument;
    const component_owned = try allocator.dupe(u8, component);

    // Collect options
    var options = std.ArrayList([]const u8){};
    while (iter.next()) |token| {
        try options.append(allocator, try allocator.dupe(u8, token));
    }

    return .{
        .loadusr = .{
            .component = component_owned,
            .options = try options.toOwnedSlice(),
            .line = line_num,
        },
    };
}

/// Parse addf command: addf function-name thread-name
fn parseAddf(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_num: usize,
) !HalCommand {
    var iter = std.mem.tokenizeScalar(u8, line, ' ');

    // Skip "addf"
    _ = iter.next();

    // Get function name
    const function_name = iter.next() orelse return error.MissingArgument;
    const function_owned = try allocator.dupe(u8, function_name);

    // Get thread name
    const thread_name = iter.next() orelse return error.MissingArgument;
    const thread_owned = try allocator.dupe(u8, thread_name);

    return .{
        .addf = .{
            .function_name = function_owned,
            .thread_name = thread_owned,
            .line = line_num,
        },
    };
}

/// Parse unlinkp command: unlinkp pin-name
fn parseUnlinkp(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_num: usize,
) !HalCommand {
    var iter = std.mem.tokenizeScalar(u8, line, ' ');

    // Skip "unlinkp"
    _ = iter.next();

    // Get pin name
    const pin_name = iter.next() orelse return error.MissingArgument;
    const pin_owned = try allocator.dupe(u8, pin_name);

    return .{
        .unlinkp = .{
            .pin_name = pin_owned,
            .line = line_num,
        },
    };
}

/// Parse a HAL value string into HalValue union
///
/// Attempts to parse as float, then int, then boolean.
fn parseHalValue(allocator: std.mem.Allocator, str: []const u8) !HalValue {
    const trimmed = std.mem.trim(u8, str, &std.ascii.whitespace);

    // Try boolean first (case-insensitive)
    const lower = toLower(allocator, trimmed);
    defer allocator.free(lower);

    if (std.mem.eql(u8, lower, "true") or
        std.mem.eql(u8, lower, "yes") or
        std.mem.eql(u8, lower, "1"))
    {
        return HalValue{ .bit = true };
    }
    if (std.mem.eql(u8, lower, "false") or
        std.mem.eql(u8, lower, "no") or
        std.mem.eql(u8, lower, "0"))
    {
        return HalValue{ .bit = false };
    }

    // Try floating point
    if (std.fmt.parseFloat(f64, trimmed)) |float_val| {
        // Check if it's actually an integer (no decimal point or exponent)
        const has_dot = std.mem.indexOfScalar(u8, trimmed, '.') != null;
        const has_exp = std.mem.indexOfScalar(u8, trimmed, 'e') != null or
            std.mem.indexOfScalar(u8, trimmed, 'E') != null;

        if (has_dot or has_exp) {
            return HalValue{ .float = float_val };
        }

        // Looks like an integer - try parsing as i32 then u32
        if (std.fmt.parseInt(i32, trimmed, 10)) |int_val| {
            return HalValue{ .s32 = int_val };
        } else |_| {
            // Too large for i32, try u32
            if (std.fmt.parseInt(u32, trimmed, 10)) |uint_val| {
                return HalValue{ .u32 = uint_val };
            } else |_| {
                // Keep as float
                return HalValue{ .float = float_val };
            }
        }
    } else |_| {}

    // Try integer parsing (signed first, then unsigned)
    if (std.fmt.parseInt(i32, trimmed, 10)) |int_val| {
        return HalValue{ .s32 = int_val };
    } else |_| {}

    if (std.fmt.parseInt(u32, trimmed, 10)) |uint_val| {
        return HalValue{ .u32 = uint_val };
    } else |_| {}

    return error.InvalidValue;
}

/// Convert string to lowercase (allocates new string)
fn toLower(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, str.len);
    for (str) |c| {
        try result.append(allocator, std.ascii.toLower(c));
    }
    return result.toOwnedSlice();
}
