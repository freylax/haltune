// .ini file parser for LinuxCNC configuration files
//
// This module parses .ini configuration files to extract:
// - [SECTIONS] with section names
// - KEY = VALUE pairs within sections
// - HALFILE directives referencing .hal files
// - POSTGUI_HALFILE directives
// - Comments (lines starting with # or ;)
//
// The parser supports:
// - Whitespace around section names and keys
// - Comments after values (using # or ;)
// - Empty lines
// - #INCLUDE directives for file inclusion

const std = @import("std");

/// INI file entry types
pub const IniEntry = union(enum) {
    /// Section header: [SECTION_NAME]
    section: struct {
        name: []const u8,
        line: usize,
    },

    /// Key-value pair: KEY = VALUE
    /// Also includes the section this entry belongs to
    key_value: struct {
        section: []const u8,
        key: []const u8,
        value: []const u8,
        line: usize,
    },

    /// Comment line (# or ; at start)
    comment: struct {
        text: []const u8,
        line: usize,
    },

    /// Include directive: #INCLUDE filename
    include: struct {
        filename: []const u8,
        line: usize,
    },

    /// HAL file reference: HALFILE = filename.hal
    halfile: struct {
        filename: []const u8,
        line: usize,
    },

    /// Post-GUI HAL file: POSTGUI_HALFILE = filename.hal
    postgui_halfile: struct {
        filename: []const u8,
        line: usize,
    },
};

/// Parse result containing all entries and metadata
pub const IniParseResult = struct {
    /// All parsed entries in file order
    entries: std.ArrayList(IniEntry),

    /// Original file path (for origin tracking)
    file_path: []const u8,

    /// Allocator used for entries
    allocator: std.mem.Allocator,

    /// Current section (for tracking section context)
    current_section: []const u8 = "",

    /// Deinitialize and free all resources
    pub fn deinit(self: *IniParseResult) void {
        // Free owned strings in entries
        for (self.entries.items) |entry| {
            switch (entry) {
                .section => |s| {
                    self.allocator.free(s.name);
                },
                .key_value => |kv| {
                    self.allocator.free(kv.section);
                    self.allocator.free(kv.key);
                    self.allocator.free(kv.value);
                },
                .comment => |c| {
                    self.allocator.free(c.text);
                },
                .include => |i| {
                    self.allocator.free(i.filename);
                },
                .halfile => |h| {
                    self.allocator.free(h.filename);
                },
                .postgui_halfile => |h| {
                    self.allocator.free(h.filename);
                },
            }
        }
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    /// Find a specific key value within a section
    pub fn findKeyValue(
        self: *const IniParseResult,
        section: []const u8,
        key: []const u8,
    ) ?[]const u8 {
        for (self.entries.items) |entry| {
            if (entry == .key_value) {
                const kv = entry.key_value;
                if (std.mem.eql(u8, kv.section, section) and
                    std.mem.eql(u8, kv.key, key))
                {
                    return kv.value;
                }
            }
        }
        return null;
    }

    /// Get all HALFILE references
    pub fn listHalfiles(self: *const IniParseResult) std.ArrayList([]const u8) {
        var files = std.ArrayList([]const u8){};

        for (self.entries.items) |entry| {
            if (entry == .halfile) {
                files.append(self.allocator, entry.halfile.filename) catch {};
            }
        }

        return files;
    }
};

/// Parse an .ini file and extract all entries with line numbers
///
/// This function reads the entire file and parses each line into
/// structured data, tracking section context.
///
/// Parameters:
///   - allocator: Memory allocator for all returned data
///   - file_path: Path to .ini file to parse
///
/// Returns:
///   - IniParseResult with all entries
///   - error.FileNotFound if file doesn't exist
///   - error.OutOfMemory if allocation fails
///
/// Thread safety:
///   - Not thread-safe (use separate parse per thread)
///
/// Example:
/// ```
/// const result = try parseIniFile(allocator, "myconfig.ini");
/// defer result.deinit();
///
/// // Find a specific value
/// if (result.findKeyValue("EMC", "MACHINE")) |machine| {
///     std.debug.print("Machine: {s}\n", .{machine});
/// }
///
/// // List all HAL files
/// const halfiles = result.listHalfiles();
/// defer {
///     halfiles.deinit(allocator);
/// }
/// ```
pub fn parseIniFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) !IniParseResult {
    var result = IniParseResult{
        .entries = std.ArrayList(IniEntry){},
        .file_path = try allocator.dupe(u8, file_path),
        .allocator = allocator,
    };

    // Read file
    const content = try std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024 * 10); // 10MB max
    defer allocator.free(content);

    // Parse each line
    var line_iter = std.mem.splitScalar(u8, content, '\n');

    var line_num: usize = 0;
    while (line_iter.next()) |line| {
        line_num += 1;

        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        // Skip empty lines
        if (trimmed.len == 0) continue;

        // Parse entry
        const entry = try parseIniLine(allocator, trimmed, line_num, &result);
        try result.entries.append(allocator, entry);
    }

    return result;
}

/// Parse a single .ini file line
///
/// Determines entry type and parses appropriately.
fn parseIniLine(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_num: usize,
    result: *IniParseResult,
) !IniEntry {
    // Check for comment
    if (isComment(line)) {
        return .{
            .comment = .{
                .text = try allocator.dupe(u8, line),
                .line = line_num,
            },
        };
    }

    // Check for section header [SECTION]
    if (line[0] == '[') {
        return parseSection(allocator, line, line_num);
    }

    // Check for include directive
    const lower_line = try toLower(allocator, line);
    defer allocator.free(lower_line);

    if (std.mem.startsWith(u8, lower_line, "#include") or
        std.mem.startsWith(u8, lower_line, "include"))
    {
        return parseInclude(allocator, line, line_num);
    }

    // Check for HALFILE or POSTGUI_HALFILE
    if (std.mem.startsWith(u8, lower_line, "halfile") or
        std.mem.startsWith(u8, lower_line, "postgui_halfile"))
    {
        return parseHalfileDirective(allocator, line, line_num);
    }

    // Default: key-value pair
    return parseKeyValue(allocator, line, line_num, result.current_section);
}

/// Check if a line is a comment
///
/// Comments start with # or ; at the beginning (ignoring leading whitespace)
fn isComment(line: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, line, &std.ascii.whitespace);
    return trimmed.len > 0 and (trimmed[0] == '#' or trimmed[0] == ';');
}

/// Parse section header: [SECTION_NAME]
fn parseSection(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_num: usize,
) !IniEntry {
    // Find closing bracket
    const end = std.mem.indexOfScalar(u8, line, ']') orelse return error.MalformedSection;

    // Extract section name (trim whitespace)
    const name = std.mem.trim(u8, line[1..end], &std.ascii.whitespace);

    return .{
        .section = .{
            .name = try allocator.dupe(u8, name),
            .line = line_num,
        },
    };
}

/// Parse key-value pair: KEY = VALUE
///
/// Handles:
/// - Whitespace around =
/// - Comments after value (using # or ;)
fn parseKeyValue(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_num: usize,
    section: []const u8,
) !IniEntry {
    // Find equals sign
    const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse return error.MalformedKeyValue;

    // Extract key (left side)
    const key = std.mem.trimRight(u8, line[0..eq_idx], &std.ascii.whitespace);

    // Extract value (right side)
    var value = line[eq_idx + 1 ..];

    // Remove trailing comment
    if (std.mem.indexOfScalar(u8, value, '#')) |hash_idx| {
        value = value[0..hash_idx];
    }
    if (std.mem.indexOfScalar(u8, value, ';')) |semi_idx| {
        value = value[0..semi_idx];
    }

    // Trim whitespace from value
    value = std.mem.trim(u8, value, &std.ascii.whitespace);

    return .{
        .key_value = .{
            .section = try allocator.dupe(u8, section),
            .key = try allocator.dupe(u8, key),
            .value = try allocator.dupe(u8, value),
            .line = line_num,
        },
    };
}

/// Parse #INCLUDE directive
fn parseInclude(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_num: usize,
) !IniEntry {
    // Skip "#INCLUDE" or "INCLUDE" keyword
    var iter = std.mem.tokenizeScalar(u8, line, ' ');

    // Skip first token (#INCLUDE, INCLUDE, #include, include)
    _ = iter.next();

    // Get filename
    const filename = iter.next() orelse return error.MissingArgument;
    const trimmed = std.mem.trim(u8, filename, &std.ascii.whitespace);

    return .{
        .include = .{
            .filename = try allocator.dupe(u8, trimmed),
            .line = line_num,
        },
    };
}

/// Parse HALFILE or POSTGUI_HALFILE directive
fn parseHalfileDirective(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_num: usize,
) !IniEntry {
    // Find equals sign
    const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse return error.MalformedKeyValue;

    // Extract key (HALFILE or POSTGUI_HALFILE)
    const key = std.mem.trimRight(u8, line[0..eq_idx], &std.ascii.whitespace);

    // Extract value
    var value = std.mem.trim(u8, line[eq_idx + 1 ..], &std.ascii.whitespace);

    // Remove trailing comment
    if (std.mem.indexOfScalar(u8, value, '#')) |hash_idx| {
        value = value[0..hash_idx];
    }
    value = std.mem.trim(u8, value, &std.ascii.whitespace);

    const lower_key = toLower(allocator, key);
    defer allocator.free(lower_key);

    if (std.mem.eql(u8, lower_key, "postgui_halfile")) {
        return .{
            .postgui_halfile = .{
                .filename = try allocator.dupe(u8, value),
                .line = line_num,
            },
        };
    }

    return .{
        .halfile = .{
            .filename = try allocator.dupe(u8, value),
            .line = line_num,
        },
    };
}

/// Convert string to lowercase (allocates new string)
fn toLower(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, str.len);
    for (str) |c| {
        try result.append(allocator, std.ascii.toLower(c));
    }
    return result.toOwnedSlice(allocator);
}
