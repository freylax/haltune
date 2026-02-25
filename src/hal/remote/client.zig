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

const protocol = @import("protocol");
const Request = protocol.Request;
const Response = protocol.Response;

/// Remote backend client state
pub const RemoteBackend = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    stream: ?std.net.Stream = null,
    comp_id: c_int = -1,

    /// Create a new remote HAL backend
    pub fn create(allocator: std.mem.Allocator, host: []const u8, port: u16) !HalBackend {
        const state = try allocator.create(State);
        state.* = .{
            .allocator = allocator,
            .host = try allocator.dupe(u8, host),
            .port = port,
            .stream = null,
            .comp_id = -1,
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

        fn connect(self: *State) !void {
            if (self.stream != null) return; // Already connected

            const address = try std.net.Address.parseIp4("127.0.0.1", self.port);
            self.stream = try std.net.tcpConnectToAddress(address);
        }

        fn disconnect(self: *State) void {
            if (self.stream) |stream| {
                stream.close();
                self.stream = null;
            }
        }

        fn sendRequest(self: *State, req: Request) !Response {
            try self.connect();

            const json = try req.toJson(self.allocator);
            defer self.allocator.free(json);

            const stream = self.stream.?;
            _ = try stream.writeAll(json);
            _ = try stream.writeAll("\n");

            // Read response
            const reader = stream.reader();
            const response_json = try reader.readAllAlloc(self.allocator, 65536);
            defer self.allocator.free(response_json);

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

    fn initComponent(ptr: *anyopaque, name: []const u8) !c_int {
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
        _ = allocator;

        const req = Request{ .list_pins = .{} };
        const resp = try self.sendRequest(req);

        // Convert response to PinInfo array
        // TODO: implement properly
        return allocator.alloc(PinInfo, 0);
    }

    fn listSignals(ptr: *anyopaque, allocator: std.mem.Allocator) ![]SignalInfo {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = allocator;

        const req = Request{ .list_signals = .{} };
        const resp = try self.sendRequest(req);

        // Convert response to SignalInfo array
        return allocator.alloc(SignalInfo, 0);
    }

    fn listParams(ptr: *anyopaque, allocator: std.mem.Allocator) ![]ParamInfo {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = allocator;

        const req = Request{ .list_params = .{} };
        const resp = try self.sendRequest(req);

        // Convert response to ParamInfo array
        return allocator.alloc(ParamInfo, 0);
    }

    fn listComponents(ptr: *anyopaque, allocator: std.mem.Allocator) ![][]const u8 {
        const self: *State = @ptrCast(@alignCast(ptr));
        _ = allocator;

        const req = Request{ .list_components = .{} };
        const resp = try self.sendRequest(req);

        // Convert response to component name array
        return allocator.alloc([]const u8, 0);
    }

    fn getPinValue(ptr: *anyopaque, name: []const u8) !HalValue {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .get_pin = .{ .name = name } };
        const resp = try self.sendRequest(req);

        return switch (resp) {
            .get_pin => |*r| r.value,
            .error_response => |*r| error.RemoteError,
            else => error.UnexpectedResponse,
        };
    }

    fn setPinValue(ptr: *anyopaque, name: []const u8, value: HalValue) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .set_pin = .{ .name = name, .value = value } };
        const resp = try self.sendRequest(req);

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
        const resp = try self.sendRequest(req);

        return switch (resp) {
            .get_param => |*r| r.value,
            .error_response => |*r| error.RemoteError,
            else => error.UnexpectedResponse,
        };
    }

    fn setParamValue(ptr: *anyopaque, name: []const u8, value: HalValue) !void {
        const self: *State = @ptrCast(@alignCast(ptr));

        const req = Request{ .set_param = .{ .name = name, .value = value } };
        const resp = try self.sendRequest(req);

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

        const req = Request{ .create_signal = .{ .name = name, .type = pin_type } };
        const resp = try self.sendRequest(req);

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
        const resp = try self.sendRequest(req);

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
        const resp = try self.sendRequest(req);

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
        const resp = try self.sendRequest(req);

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
