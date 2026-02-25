// HAL Bridge Protocol
//
// JSON message format for HAL bridge client/server communication.

const std = @import("std");
const backend = @import("backend");
const PinType = backend.PinType;
const HalValue = backend.HalValue;

/// Message types
pub const MessageType = enum {
    // Requests
    list_pins,
    list_signals,
    list_params,
    list_components,
    get_pin,
    set_pin,
    get_param,
    set_param,
    create_signal,
    delete_signal,
    link_pin,
    unlink_pin,
    ping,

    // Responses
    error_response,

    pub fn fromString(s: []const u8) ?MessageType {
        const map = std.ComptimeStringMap(MessageType, .{
            .{ "list_pins", .list_pins },
            .{ "list_signals", .list_signals },
            .{ "list_params", .list_params },
            .{ "list_components", .list_components },
            .{ "get_pin", .get_pin },
            .{ "set_pin", .set_pin },
            .{ "get_param", .get_param },
            .{ "set_param", .set_param },
            .{ "create_signal", .create_signal },
            .{ "delete_signal", .delete_signal },
            .{ "link_pin", .link_pin },
            .{ "unlink_pin", .unlink_pin },
            .{ "ping", .ping },
            .{ "error", .error_response },
        });
        return map.get(s);
    }

    pub fn toString(comptime self: MessageType) []const u8 {
        return switch (self) {
            .list_pins => "list_pins",
            .list_signals => "list_signals",
            .list_params => "list_params",
            .list_components => "list_components",
            .get_pin => "get_pin",
            .set_pin => "set_pin",
            .get_param => "get_param",
            .set_param => "set_param",
            .create_signal => "create_signal",
            .delete_signal => "delete_signal",
            .link_pin => "link_pin",
            .unlink_pin => "unlink_pin",
            .ping => "ping",
            .error_response => "error",
        };
    }
};

/// Request message
pub const Request = union(MessageType) {
    list_pins: struct {},
    list_signals: struct {},
    list_params: struct {},
    list_components: struct {},
    get_pin: struct { name: []const u8 },
    set_pin: struct { name: []const u8, value: HalValue },
    get_param: struct { name: []const u8 },
    set_param: struct { name: []const u8, value: HalValue },
    create_signal: struct { name: []const u8, type: PinType },
    delete_signal: struct { name: []const u8 },
    link_pin: struct { pin_name: []const u8, sig_name: []const u8 },
    unlink_pin: struct { name: []const u8 },
    ping: struct {},

    /// Serialize request to JSON
    pub fn toJson(self: Request, allocator: std.mem.Allocator) ![]const u8 {
        const tag = std.meta.activeTag(self);

        var json_buffer = std.ArrayList(u8).init(allocator);
        defer json_buffer.deinit();

        const writer = json_buffer.writer();
        try writer.writeAll("{\"type\":\"");
        try writer.writeAll(tag.toString());
        try writer.writeAll("\"");

        // Add fields based on type
        switch (self) {
            .list_pins, .list_signals, .list_params, .list_components, .ping => {},
            .get_pin, .get_param, .delete_signal, .unlink_pin => |*data| {
                try writer.print(",\"name\":\"{s}\"", .{data.name});
            },
            .set_pin, .set_param => |*data| {
                try writer.print(",\"name\":\"{s}\",\"value\":", .{data.name});
                try writeHalValue(writer, data.value);
            },
            .create_signal => |*data| {
                try writer.print(",\"name\":\"{s}\",\"type\":\"{s}\"", .{ data.name, @tagName(data.type) });
            },
            .link_pin => |*data| {
                try writer.print(",\"pin_name\":\"{s}\",\"sig_name\":\"{s}\"", .{ data.pin_name, data.sig_name });
            },
        }

        try writer.writeAll("}");
        return allocator.dupe(u8, json_buffer.items);
    }

    fn writeHalValue(writer: anytype, value: HalValue) !void {
        try writer.writeAll("{");
        switch (value) {
            .bit => |v| try writer.print("\"bit\":{}", .{v}),
            .float => |v| try writer.print("\"float\":{d}", .{v}),
            .s32 => |v| try writer.print("\"s32\":{}", .{v}),
            .u32 => |v| try writer.print("\"u32\":{}", .{v}),
        }
        try writer.writeAll("}");
    }
};

/// Response message
pub const Response = union(MessageType) {
    list_pins: struct { pins: []PinInfoResponse },
    list_signals: struct { signals: []SignalInfoResponse },
    list_params: struct { params: []ParamInfoResponse },
    list_components: struct { components: [][]const u8 },
    get_pin: struct { value: HalValue },
    set_pin: struct { success: bool },
    get_param: struct { value: HalValue },
    set_param: struct { success: bool },
    create_signal: struct { success: bool },
    delete_signal: struct { success: bool },
    link_pin: struct { success: bool },
    unlink_pin: struct { success: bool },
    ping: struct {},
    error_response: struct { message: []const u8 },

    pub const PinInfoResponse = struct {
        name: []const u8,
        type: PinType,
        dir: backend.PinDir,
        value: HalValue,
    };

    pub const SignalInfoResponse = struct {
        name: []const u8,
        type: PinType,
        value: HalValue,
        writers: []const []const u8,
        readers: []const []const u8,
    };

    pub const ParamInfoResponse = struct {
        name: []const u8,
        type: PinType,
        dir: backend.ParamDir,
        value: HalValue,
    };

    /// Parse response from JSON
    pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !Response {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{
            .ignore_duplicate_fields = true,
            .allocate = .alloc_always,
        });
        defer parsed.deinit();

        const obj = parsed.value.object;
        const type_str = obj.get("type").?.string;

        const msg_type = MessageType.fromString(type_str) orelse return error.InvalidMessageType;

        return switch (msg_type) {
            .list_pins => Response{
                .list_pins = .{ .pins = &.{} }, // TODO: parse array
            },
            .list_signals => Response{
                .list_signals = .{ .signals = &.{} },
            },
            .list_params => Response{
                .list_params = .{ .params = &.{} },
            },
            .list_components => Response{
                .list_components = .{ .components = &.{} },
            },
            .get_pin => Response{
                .get_pin = .{ .value = try parseHalValue(obj.get("value").?) },
            },
            .set_pin => Response{
                .set_pin = .{ .success = obj.get("success").?.bool },
            },
            .get_param => Response{
                .get_param = .{ .value = try parseHalValue(obj.get("value").?) },
            },
            .set_param => Response{
                .set_param = .{ .success = obj.get("success").?.bool },
            },
            .create_signal => Response{
                .create_signal = .{ .success = obj.get("success").?.bool },
            },
            .delete_signal => Response{
                .delete_signal = .{ .success = obj.get("success").?.bool },
            },
            .link_pin => Response{
                .link_pin = .{ .success = obj.get("success").?.bool },
            },
            .unlink_pin => Response{
                .unlink_pin = .{ .success = obj.get("success").?.bool },
            },
            .ping => Response{ .ping = .{} },
            .error_response => Response{
                .error_response = .{ .message = obj.get("message").?.string },
            },
        };
    }

    fn parseHalValue(value_node: *const std.json.Value) !HalValue {
        const obj = value_node.object;
        if (obj.get("bit")) |v| {
            return HalValue{ .bit = v.bool };
        }
        if (obj.get("float")) |v| {
            return HalValue{ .float = v.float };
        }
        if (obj.get("s32")) |v| {
            return HalValue{ .s32 = @intCast(v.integer) };
        }
        if (obj.get("u32")) |v| {
            return HalValue{ .u32 = @intCast(v.integer) };
        }
        return error.InvalidHalValue;
    }
};

// Tests
test "Request serialization - ping" {
    const req = Request{ .ping = .{} };
    const json = try req.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings("{\"type\":\"ping\"}", json);
}

test "Request serialization - get_pin" {
    const req = Request{ .get_pin = .{ .name = "test.pin" } };
    const json = try req.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings("{\"type\":\"get_pin\",\"name\":\"test.pin\"}", json);
}
