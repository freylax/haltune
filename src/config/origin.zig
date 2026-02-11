// Configuration origin tracking for HAL items
//
// This module provides data structures and functions for tracking
// where each HAL pin, parameter, or signal value came from.
//
// Origins can be:
// - .hal file (setp command)
// - .ini file (variable reference)
// - Component default (no explicit setting)
// - Runtime modified (changed after load via halcmd/haltune)

const std = @import("std");

/// Origin type for a HAL item value
pub const Origin = enum(u8) {
    /// No explicit origin (component default)
    none = 0,

    /// Value set from .hal file (setp command)
    hal_file = 1,

    /// Value from .ini file variable
    ini_file = 2,

    /// Component default value
    default_value = 3,

    /// Modified at runtime after initial load
    runtime_modified = 4,
};

/// Origin information for a single HAL item
pub const ItemOrigin = struct {
    /// Where this value came from
    origin: Origin,

    /// File path where this value was set (if applicable)
    file_path: ?[]const u8,

    /// Line number in file where value was set (if applicable)
    line: ?usize,

    /// For .ini items: section name
    ini_section: ?[]const u8,

    /// For .ini items: variable name
    ini_variable: ?[]const u8,

    /// Create a new ItemOrigin with no origin
    pub fn none() ItemOrigin {
        return .{
            .origin = .none,
            .file_path = null,
            .line = null,
            .ini_section = null,
            .ini_variable = null,
        };
    }

    /// Create origin from .hal file
    pub fn fromHalFile(
        allocator: std.mem.Allocator,
        file_path: []const u8,
        line: usize,
    ) !ItemOrigin {
        return .{
            .origin = .hal_file,
            .file_path = try allocator.dupe(u8, file_path),
            .line = line,
            .ini_section = null,
            .ini_variable = null,
        };
    }

    /// Create origin from .ini file
    pub fn fromIniFile(
        allocator: std.mem.Allocator,
        file_path: []const u8,
        section: []const u8,
        variable: []const u8,
        line: usize,
    ) !ItemOrigin {
        return .{
            .origin = .ini_file,
            .file_path = try allocator.dupe(u8, file_path),
            .line = line,
            .ini_section = try allocator.dupe(u8, section),
            .ini_variable = try allocator.dupe(u8, variable),
        };
    }

    /// Mark as runtime modified
    pub fn runtimeModified(self: *ItemOrigin) void {
        self.origin = .runtime_modified;
    }

    /// Free allocated resources
    pub fn deinit(self: *ItemOrigin, allocator: std.mem.Allocator) void {
        if (self.file_path) |p| allocator.free(p);
        if (self.ini_section) |s| allocator.free(s);
        if (self.ini_variable) |v| allocator.free(v);
        self.* = undefined;
    }

    /// Format origin as display string
    pub fn format(self: *const ItemOrigin, writer: anytype) !void {
        switch (self.origin) {
            .none => try writer.writeAll("(default)"),
            .hal_file => {
                if (self.file_path) |p| {
                    // Extract just filename from path
                    const filename = std.fs.path.basename(p);
                    try writer.print("{s}", .{filename});
                    if (self.line) |l| {
                        try writer.print(":{}", .{l});
                    }
                } else {
                    try writer.writeAll(".hal file");
                }
            },
            .ini_file => {
                if (self.ini_section) |sec| {
                    if (self.ini_variable) |ini_var| {
                        try writer.print("[{s}]{s}", .{ sec, ini_var });
                    } else {
                        try writer.print("[{s}]", .{sec});
                    }
                } else {
                    try writer.writeAll(".ini file");
                }
            },
            .default_value => try writer.writeAll("(component default)"),
            .runtime_modified => try writer.writeAll("(modified at runtime)"),
        }
    }
};

/// Origin tracking store for HAL items
///
/// This structure maintains separate maps for pins, parameters, and signals
/// to track where each value came from.
pub const OriginTracker = struct {
    allocator: std.mem.Allocator,

    /// Map pin name -> origin
    pin_origins: std.StringHashMap(ItemOrigin),

    /// Map parameter name -> origin
    param_origins: std.StringHashMap(ItemOrigin),

    /// Map signal name -> origin
    signal_origins: std.StringHashMap(ItemOrigin),

    /// Initialize a new OriginTracker
    pub fn init(allocator: std.mem.Allocator) OriginTracker {
        return .{
            .allocator = allocator,
            .pin_origins = std.StringHashMap(ItemOrigin).init(allocator),
            .param_origins = std.StringHashMap(ItemOrigin).init(allocator),
            .signal_origins = std.StringHashMap(ItemOrigin).init(allocator),
        };
    }

    /// Clean up OriginTracker and free all resources
    pub fn deinit(self: *OriginTracker) void {
        // Free all ItemOrigin entries
        {
            var iter = self.pin_origins.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.deinit(self.allocator);
                self.allocator.free(entry.key_ptr.*);
            }
        }
        self.pin_origins.deinit();

        {
            var iter = self.param_origins.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.deinit(self.allocator);
                self.allocator.free(entry.key_ptr.*);
            }
        }
        self.param_origins.deinit();

        {
            var iter = self.signal_origins.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.deinit(self.allocator);
                self.allocator.free(entry.key_ptr.*);
            }
        }
        self.signal_origins.deinit();
    }

    /// Get origin for a pin
    pub fn getPinOrigin(self: *const OriginTracker, name: []const u8) ?ItemOrigin {
        return self.pin_origins.get(name);
    }

    /// Get origin for a parameter
    pub fn getParamOrigin(self: *const OriginTracker, name: []const u8) ?ItemOrigin {
        return self.param_origins.get(name);
    }

    /// Get origin for a signal
    pub fn getSignalOrigin(self: *const OriginTracker, name: []const u8) ?ItemOrigin {
        return self.signal_origins.get(name);
    }

    /// Set origin for a pin
    pub fn setPinOrigin(
        self: *OriginTracker,
        name: []const u8,
        origin: ItemOrigin,
    ) !void {
        // Remove existing entry if present
        if (self.pin_origins.fetchRemove(name)) |entry| {
            entry.value.deinit(self.allocator);
            self.allocator.free(entry.key);
        }

        // Add new entry with owned key
        const name_owned = try self.allocator.dupe(u8, name);
        try self.pin_origins.put(name_owned, origin);
    }

    /// Set origin for a parameter
    pub fn setParamOrigin(
        self: *OriginTracker,
        name: []const u8,
        origin: ItemOrigin,
    ) !void {
        // Remove existing entry if present
        if (self.param_origins.fetchRemove(name)) |entry| {
            entry.value.deinit(self.allocator);
            self.allocator.free(entry.key);
        }

        // Add new entry with owned key
        const name_owned = try self.allocator.dupe(u8, name);
        try self.param_origins.put(name_owned, origin);
    }

    /// Set origin for a signal
    pub fn setSignalOrigin(
        self: *OriginTracker,
        name: []const u8,
        origin: ItemOrigin,
    ) !void {
        // Remove existing entry if present
        if (self.signal_origins.fetchRemove(name)) |entry| {
            entry.value.deinit(self.allocator);
            self.allocator.free(entry.key);
        }

        // Add new entry with owned key
        const name_owned = try self.allocator.dupe(u8, name);
        try self.signal_origins.put(name_owned, origin);
    }

    /// Mark all tracked items as runtime modified
    ///
    /// Call this after parsing files when user makes changes via TUI
    pub fn markRuntimeModified(self: *OriginTracker, name: []const u8) !void {
        // Check and update in all maps
        if (self.pin_origins.getEntry(name)) |entry| {
            entry.value_ptr.*.runtimeModified();
        } else if (self.param_origins.getEntry(name)) |entry| {
            entry.value_ptr.*.runtimeModified();
        } else if (self.signal_origins.getEntry(name)) |entry| {
            entry.value_ptr.*.runtimeModified();
        }
    }
};

/// Configuration file metadata for origin tracking
///
/// Tracks which files were loaded and their contents for
/// generating file write-back commands.
pub const ConfigMetadata = struct {
    allocator: std.mem.Allocator,

    /// List of .hal files that were loaded
    hal_files: std.ArrayList([]const u8),

    /// List of .ini files that were loaded
    ini_files: std.ArrayList([]const u8),

    /// Initialize ConfigMetadata
    pub fn init(allocator: std.mem.Allocator) ConfigMetadata {
        return .{
            .allocator = allocator,
            .hal_files = std.ArrayList([]const u8).init(allocator),
            .ini_files = std.ArrayList([]const u8).init(allocator),
        };
    }

    /// Clean up ConfigMetadata
    pub fn deinit(self: *ConfigMetadata) void {
        for (self.hal_files.items) |file| {
            self.allocator.free(file);
        }
        self.hal_files.deinit();

        for (self.ini_files.items) |file| {
            self.allocator.free(file);
        }
        self.ini_files.deinit();
    }

    /// Add a .hal file to metadata
    pub fn addHalFile(self: *ConfigMetadata, path: []const u8) !void {
        const path_owned = try self.allocator.dupe(u8, path);
        try self.hal_files.append(path_owned);
    }

    /// Add an .ini file to metadata
    pub fn addIniFile(self: *ConfigMetadata, path: []const u8) !void {
        const path_owned = try self.allocator.dupe(u8, path);
        try self.ini_files.append(path_owned);
    }

    /// Check if a .hal file has been loaded
    pub fn hasHalFile(self: *const ConfigMetadata, path: []const u8) bool {
        for (self.hal_files.items) |file| {
            if (std.mem.eql(u8, file, path)) return true;
        }
        return false;
    }
};
