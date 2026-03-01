// Remote HAL Backend Client
//
// This implementation connects to a HAL bridge server over TCP.

const std = @import("std");
const backend = @import("backend");
const HalBackend = backend.HalBackend;
const HalValue = backend.HalValue;
const PinInfo = backend.PinInfo;
const SignalInfo = backend.SignalInfo;
const ParamInfo = backend.ParamInfo;
const PinType = backend.PinType;
const PinDir = backend.PinDir;
const ParamDir = backend.ParamDir;

const protocol = @import("../hal_protocol.zig");
const Request = protocol.Request;
const Response = protocol.Response;

// C setsockopt for setting socket timeout
const c_socket = @cImport({
    @cDefine("_DEFAULT_SOURCE", "");
    @cInclude("sys/socket.h");
    @cInclude("sys/time.h");
});

/// Remote backend client state
pub const RemoteBackend = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    stream: ?std.net.Stream = null,
    comp_id: c_int = -1,
    mutex: std.Thread.Mutex, // Protect stream access

    /// Create a new remote HAL backend
    pub fn create(allocator: std.mem.Allocator, host: []const u8, port: u16) !HalBackend {
        const state = try allocator.create(State);
        state.* = .{
            .allocator = allocator,
            .host = try allocator.dupe(u8, host),
            .port = port,
            .stream = null,
            .comp_id = -1,
            .mutex = std.Thread.Mutex{},
        };

        return HalBackend{
            .ptr = state,
            .vtable = &vtable,
        };
    }

    const State = struct {
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
        stream: ?std.net.Stream,
        comp_id: c_int,
        mutex: std.Thread.Mutex, // Protect stream access

        fn connect(self: *State) !void {
            if (self.stream != null) return; // Already connected

            std.log.err("DEBUG Remote: Connecting to {s}:{}", .{self.host, self.port});
            const address = std.net.Address.parseIp4(self.host, self.port) catch |err| {
                std.log.err("Remote: parseIp4 failed: {}", .{err});
                return error.RemoteError;
            };
            self.stream = std.net.tcpConnectToAddress(address) catch |err| {
                std.log.err("Remote: tcpConnectToAddress failed: {}", .{err});
                return error.RemoteError;
            };

            // Set socket receive timeout (30 seconds for large responses)
            const stream = self.stream.?;
            const fd = stream.handle;
            var timeout = c_socket.struct_timeval{
                .tv_sec = 30,
                .tv_usec = 0,
            };
            const rc = c_socket.setsockopt(
                fd,
                c_socket.SOL_SOCKET,
                c_socket.SO_RCVTIMEO,
                &timeout,
                @sizeOf(c_socket.struct_timeval),
            );
            if (rc != 0) {
                std.log.err("Remote: failed to set socket timeout (rc={})", .{rc});
                // Continue anyway - timeout is nice-to-have, not critical
            }

            std.log.err("DEBUG Remote: Connected successfully (with 30s timeout)", .{});
        }

        fn disconnect(self: *State) void {
            if (self.stream) |stream| {
                stream.close();
                self.stream = null;
            }
        }

        fn sendRequest(self: *State, req: Request) !Response {
            std.log.err("DEBUG Remote: sendRequest() called", .{});

            // Lock mutex to protect stream access
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.connect();

            const json = try req.toJson(self.allocator);
            defer self.allocator.free(json);

            std.log.err("DEBUG Remote: Sending request: {s}", .{json});

            const stream = self.stream.?; // Must be non-null after connect()
            _ = try stream.writeAll(json);
            _ = try stream.writeAll("\n");

            std.log.err("DEBUG Remote: Request sent, waiting for response...", .{});

            // Read response - accumulate data in ArrayList (Zig 0.15 API)
            var buffer_list = try std.ArrayList(u8).initCapacity(self.allocator, 1024);
            defer buffer_list.deinit(self.allocator);

            var read_buf: [1024]u8 = undefined;
            var total_read: usize = 0;
            while (true) {
                const bytes_read = stream.read(&read_buf) catch |err| {
                    std.log.err("DEBUG Remote: read() failed with error: {} (total_read={})", .{err, total_read});
                    return error.RemoteError;
                };
                if (bytes_read == 0) {
                    std.log.err("Remote: connection closed by server (total_read={})", .{total_read});
                    return error.RemoteError;
                }
                total_read += bytes_read;
                try buffer_list.appendSlice(self.allocator, read_buf[0..bytes_read]);
                // Check if we have a complete JSON response (ending with \n)
                if (buffer_list.getLastOrNull()) |last| {
                    if (last == '\n') break;
                }
            }

            const response_json = try buffer_list.toOwnedSlice(self.allocator);
            defer self.allocator.free(response_json);

            std.log.err("DEBUG Remote: Received response (len={d}): {s}", .{response_json.len, response_json[0..@min(response_json.len, 200)]});

            return try Response.fromJson(self.allocator, response_json);
        }
    };

    const vtable = HalBackend.VTable{
        .deinit = deinit,
        .initComponent = initComponent,
        .readyComponent = readyComponent,
        .exitComponent = exitComponent,
        .listPins = listPins,
        .listSignals = listSignals,
        .listParams = listParams,
        .listComponents = listComponents,
        .getPinValue = getPinValue,
        .setPinValue = setPinValue,
        .getParamValue = getParamValue,
        .setParamValue = setParamValue,
        .createSignal = createSignal,
        .deleteSignal = deleteSignal,
        .linkPin = linkPin,
        .unlinkPin = unlinkPin,
    };

    fn deinit(ptr: *anyopaque) void {
        const self: *State = @ptrCast(@alignCast(ptr));
        self.disconnect();
        self.allocator.free(self.host);
        self.allocator.destroy(self);
    }

    fn initComponent(ptr: *anyopaque, name_: []const u8) !c_int {
        _ = name_;
        const self: *State = @ptrCast(@alignCast(ptr));

        // For remote backend, we don't actually create a component on the server
        // The bridge server creates its own component
        // Just return a fake comp_id
        self.comp_id = 1;
        return self.comp_id;
    }

    fn readyComponent(ptr: *anyopaque, comp_id: c_int) !void {
        _ = comp_id;
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = self;
        // No-op for remote backend
    }

    fn exitComponent(ptr: *anyopaque, comp_id: c_int) void {
        _ = comp_id;
        const self: *State = @ptrCast(@alignCast(ptr));
        self.disconnect();
    }

    fn listPins(ptr: *anyopaque, allocator: std.mem.Allocator) ![]PinInfo {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .list_pins = .{} };
        const resp = self.sendRequest(req) catch |err| {
            std.log.err("listPins: sendRequest failed with error: {}", .{err});
            return error.RemoteError;
        };

        std.log.err("listPins: got response, checking type...", .{});

        switch (resp) {
            .list_pins => |r| {
                std.log.err("listPins: response has {} pins", .{r.pins.len});

                // Convert from protocol.PinInfoResponse to backend.PinInfo
                // Note: we own the memory from r.pins now
                var result = try std.ArrayList(PinInfo).initCapacity(allocator, r.pins.len);
                errdefer result.deinit(allocator);

                for (r.pins, 0..) |pin_resp, i| {
                    // Duplicate the name so we own the memory
                    const name_dup = allocator.dupe(u8, pin_resp.name) catch |err| {
                        std.log.err("listPins: failed to dupe pin name {}: {}", .{i, err});
                        return err;
                    };
                    try result.append(allocator, .{
                        .name = name_dup,
                        .type = pin_resp.type,
                        .dir = pin_resp.dir,
                        .value = pin_resp.value,
                    });
                }

                const owned_slice = try result.toOwnedSlice(allocator);
                std.log.err("listPins: returning {} pins", .{owned_slice.len});
                // Note: r.pins memory will be freed when resp is deinitialized
                // We've taken ownership of the names by duplicating them
                return owned_slice;
            },
            .error_response => |_| return error.RemoteError,
            else => return error.UnexpectedResponse,
        }
    }

    fn listSignals(ptr: *anyopaque, allocator: std.mem.Allocator) ![]SignalInfo {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .list_signals = .{} };
        const resp = self.sendRequest(req) catch return error.RemoteError;

        switch (resp) {
            .list_signals => |r| {
                // Convert from protocol.SignalInfoResponse to backend.SignalInfo
                var result = try std.ArrayList(SignalInfo).initCapacity(allocator, r.signals.len);
                errdefer result.deinit(allocator);

                for (r.signals) |sig_resp| {
                    // Duplicate the name
                    const name_dup = try allocator.dupe(u8, sig_resp.name);

                    // Duplicate writers array
                    const writers_dup = try allocator.alloc([]const u8, sig_resp.writers.len);
                    for (sig_resp.writers, 0..) |w, i| {
                        writers_dup[i] = try allocator.dupe(u8, w);
                    }

                    // Duplicate readers array
                    const readers_dup = try allocator.alloc([]const u8, sig_resp.readers.len);
                    for (sig_resp.readers, 0..) |reader, i| {
                        readers_dup[i] = try allocator.dupe(u8, reader);
                    }

                    try result.append(allocator, .{
                        .name = name_dup,
                        .type = sig_resp.type,
                        .value = sig_resp.value,
                        .writers = writers_dup,
                        .readers = readers_dup,
                    });
                }

                const owned_slice = try result.toOwnedSlice(allocator);
                // Note: r.signals memory will be freed when resp is deinitialized
                // We've taken ownership of the names by duplicating them
                return owned_slice;
            },
            .error_response => |_| return error.RemoteError,
            else => return error.UnexpectedResponse,
        }
    }

    fn listParams(ptr: *anyopaque, allocator: std.mem.Allocator) ![]ParamInfo {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .list_params = .{} };
        const resp = self.sendRequest(req) catch return error.RemoteError;

        switch (resp) {
            .list_params => |r| {
                // Convert from protocol.ParamInfoResponse to backend.ParamInfo
                var result = try std.ArrayList(ParamInfo).initCapacity(allocator, r.params.len);
                errdefer result.deinit(allocator);

                for (r.params) |param_resp| {
                    // Duplicate the name
                    const name_dup = try allocator.dupe(u8, param_resp.name);
                    try result.append(allocator, .{
                        .name = name_dup,
                        .type = param_resp.type,
                        .dir = param_resp.dir,
                        .value = param_resp.value,
                    });
                }

                const owned_slice = try result.toOwnedSlice(allocator);
                // Note: r.params memory will be freed when resp is deinitialized
                // We've taken ownership of the names by duplicating them
                return owned_slice;
            },
            .error_response => |_| return error.RemoteError,
            else => return error.UnexpectedResponse,
        }
    }

    fn listComponents(ptr: *anyopaque, allocator: std.mem.Allocator) ![][]const u8 {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .list_components = .{} };
        const resp = self.sendRequest(req) catch return error.RemoteError;

        switch (resp) {
            .list_components => |r| {
                // Components are already [][]const u8 - need to copy
                var result = try std.ArrayList([]const u8).initCapacity(allocator, r.components.len);
                errdefer result.deinit(allocator);
                errdefer {
                    for (result.items) |c| allocator.free(c);
                }

                for (r.components) |comp| {
                    try result.append(allocator, try allocator.dupe(u8, comp));
                }

                return result.toOwnedSlice(allocator);
            },
            .error_response => |_| return error.RemoteError,
            else => return error.UnexpectedResponse,
        }
    }

    fn getPinValue(ptr: *anyopaque, name: []const u8) !HalValue {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .get_pin = .{ .name = name } };
        const resp = self.sendRequest(req) catch return error.RemoteError;

        return switch (resp) {
            .get_pin => |*r| r.value,
            .error_response => |_| error.RemoteError,
            else => error.UnexpectedResponse,
        };
    }

    fn setPinValue(ptr: *anyopaque, name: []const u8, value: HalValue) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .set_pin = .{ .name = name, .value = value } };
        const resp = self.sendRequest(req) catch return error.RemoteError;

        switch (resp) {
            .set_pin => |*r| {
                if (!r.success) return error.RemoteError;
            },
            .error_response => |*r| {
                std.log.err("Remote error: {s}", .{r.message});
                return error.RemoteError;
            },
            else => return error.UnexpectedResponse,
        }
    }

    fn getParamValue(ptr: *anyopaque, name: []const u8) !HalValue {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .get_param = .{ .name = name } };
        const resp = self.sendRequest(req) catch return error.RemoteError;

        return switch (resp) {
            .get_param => |*r| r.value,
            .error_response => |_| error.RemoteError,
            else => error.UnexpectedResponse,
        };
    }

    fn setParamValue(ptr: *anyopaque, name: []const u8, value: HalValue) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .set_param = .{ .name = name, .value = value } };
        const resp = self.sendRequest(req) catch return error.RemoteError;

        switch (resp) {
            .set_param => |*r| {
                if (!r.success) return error.RemoteError;
            },
            .error_response => |*r| {
                std.log.err("Remote error: {s}", .{r.message});
                return error.RemoteError;
            },
            else => return error.UnexpectedResponse,
        }
    }

    fn createSignal(ptr: *anyopaque, name: []const u8, pin_type: PinType) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .create_signal = .{ .name = name, .pin_type = pin_type } };
        const resp = self.sendRequest(req) catch return error.RemoteError;

        switch (resp) {
            .create_signal => |*r| {
                if (!r.success) return error.RemoteError;
            },
            .error_response => |*r| {
                std.log.err("Remote error: {s}", .{r.message});
                return error.RemoteError;
            },
            else => return error.UnexpectedResponse,
        }
    }

    fn deleteSignal(ptr: *anyopaque, name: []const u8) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .delete_signal = .{ .name = name } };
        const resp = self.sendRequest(req) catch return error.RemoteError;

        switch (resp) {
            .delete_signal => |*r| {
                if (!r.success) return error.RemoteError;
            },
            .error_response => |*r| {
                std.log.err("Remote error: {s}", .{r.message});
                return error.RemoteError;
            },
            else => return error.UnexpectedResponse,
        }
    }

    fn linkPin(ptr: *anyopaque, pin_name: []const u8, sig_name: []const u8) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .link_pin = .{ .pin_name = pin_name, .sig_name = sig_name } };
        const resp = self.sendRequest(req) catch return error.RemoteError;

        switch (resp) {
            .link_pin => |*r| {
                if (!r.success) return error.RemoteError;
            },
            .error_response => |*r| {
                std.log.err("Remote error: {s}", .{r.message});
                return error.RemoteError;
            },
            else => return error.UnexpectedResponse,
        }
    }

    fn unlinkPin(ptr: *anyopaque, pin_name: []const u8) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .unlink_pin = .{ .name = pin_name } };
        const resp = self.sendRequest(req) catch return error.RemoteError;

        switch (resp) {
            .unlink_pin => |*r| {
                if (!r.success) return error.RemoteError;
            },
            .error_response => |*r| {
                std.log.err("Remote error: {s}", .{r.message});
                return error.RemoteError;
            },
            else => return error.UnexpectedResponse,
        }
    }
};
