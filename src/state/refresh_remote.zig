// Remote HAL refresh for haltune
//
// This module provides remote HAL refresh functionality that connects
// to the HAL bridge server instead of using local HAL.

const std = @import("std");
const StateStore = @import("cache.zig").StateStore;
const HalValue = @import("cache.zig").HalValue;
const backend = @import("backend");
const RemoteBackend = @import("../../hal/remote/client.zig").RemoteBackend;

/// Remote HAL refresh module
///
/// Connects to HAL bridge server and refreshes state from remote HAL.
pub const RemoteRefresh = struct {
    store: *StateStore,
    backend: *backend.HalBackend,
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,

    /// Initialize remote HAL backend
    pub fn init(
        allocator: std.mem.Allocator,
        store: *StateStore,
        host: []const u8,
        port: u16,
    ) !RemoteRefresh {
        // Create remote backend
        const hal_backend = try RemoteBackend.create(allocator, host, port);

        return .{
            .store = store,
            .backend = try allocator.create(backend.HalBackend),
            .allocator = allocator,
            .host = host,
            .port = port,
        };
    }

    /// Deinitialize remote backend
    pub fn deinit(self: *RemoteRefresh) void {
        self.backend.deinit();
        self.allocator.destroy(self.backend);
    }

    /// Refresh all data from remote HAL server
    pub fn refreshAll(self: *RemoteRefresh) !void {
        // Refresh pins
        try self.refreshPins();

        // Refresh signals
        try self.refreshSignals();

        // Refresh params
        try self.refreshParams();
    }

    /// Refresh pins from remote HAL
    fn refreshPins(self: *RemoteRefresh) !void {
        const pin_infos = try self.backend.listPins(self.allocator);
        defer {
            for (pin_infos) |pin| {
                self.allocator.free(pin.name);
            }
            self.allocator.free(pin_infos);
        }

        // Track discovered names
        var discovered = std.StringHashMap(void).init(self.allocator);
        defer {
            var iter = discovered.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            discovered.deinit();
        }

        // Process each pin
        for (pin_infos) |pin| {
            const name_copy = try self.allocator.dupe(u8, pin.name);
            try discovered.put(name_copy, {});

            // Get current value and update store
            const value = try self.backend.getPinValue(pin.name);
            try self.store.updatePin(pin.name, value, pin.type, pin.dir);
        }

        // Remove stale pins
        const cached = try self.store.listPinNames();
        defer {
            for (cached) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(cached);
        }

        for (cached) |name| {
            if (discovered.get(name) == null) {
                self.store.removePin(name) catch {};
            }
        }
    }

    /// Refresh signals from remote HAL
    fn refreshSignals(self: *RemoteRefresh) !void {
        const signal_infos = try self.backend.listSignals(self.allocator);
        defer {
            for (signal_infos) |sig| {
                self.allocator.free(sig.name);
                self.allocator.free(sig.writers);
                self.allocator.free(sig.readers);
            }
            self.allocator.free(signal_infos);
        }

        // Track discovered names
        var discovered = std.StringHashMap(void).init(self.allocator);
        defer {
            var iter = discovered.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            discovered.deinit();
        }

        // Process each signal
        for (signal_infos) |sig| {
            const name_copy = try self.allocator.dupe(u8, sig.name);
            try discovered.put(name_copy, {});

            // Get current value and update store
            // Note: backend.listSignals should include values
            // For now, just track existence
            _ = sig;
        }

        // Remove stale signals
        const cached = try self.store.listSignalNames();
        defer {
            for (cached) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(cached);
        }

        for (cached) |name| {
            if (discovered.get(name) == null) {
                self.store.removeSignal(name) catch {};
            }
        }
    }

    /// Refresh params from remote HAL
    fn refreshParams(self: *RemoteRefresh) !void {
        const param_infos = try self.backend.listParams(self.allocator);
        defer {
            for (param_infos) |param| {
                self.allocator.free(param.name);
            }
            self.allocator.free(param_infos);
        }

        // Track discovered names
        var discovered = std.StringHashMap(void).init(self.allocator);
        defer {
            var iter = discovered.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            discovered.deinit();
        }

        // Process each param
        for (param_infos) |param| {
            const name_copy = try self.allocator.dupe(u8, param.name);
            try discovered.put(name_copy, {});

            // Get current value and update store
            const value = try self.backend.getParamValue(param.name);
            try self.store.updateParam(param.name, value, param.type, param.dir);
        }

        // Remove stale params
        const cached = try self.store.listParamNames();
        defer {
            for (cached) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(cached);
        }

        for (cached) |name| {
            if (discovered.get(name) == null) {
                self.store.removeParam(name) catch {};
            }
        }
    }
};
