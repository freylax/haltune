// HAL Bridge Protocol
//
// JSON message format for HAL bridge client/server communication.

const std = @import("std");
const backend = @import("../backend.zig");
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
        const map = std.StaticStringMap(MessageType).initComptime(.{
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

    pub fn toString(self: MessageType) []const u8 {
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
    create_signal: struct { name: []const u8, pin_type: PinType },
    delete_signal: struct { name: []const u8 },
    link_pin: struct { pin_name: []const u8, sig_name: []const u8 },
    unlink_pin: struct { name: []const u8 },
    ping: struct {},
    error_response: struct { message: []const u8 },

    /// Serialize request to JSON
    pub fn toJson(self: Request, allocator: std.mem.Allocator) ![]const u8 {
        const tag = std.meta.activeTag(self);

        var json_buffer = try std.ArrayList(u8).initCapacity(allocator, 256);
        defer json_buffer.deinit(allocator);

        const writer = json_buffer.writer(allocator);
        try writer.writeAll("{\"type\":\"");
        try writer.writeAll(tag.toString());
        try writer.writeAll("\"");

        // Add fields based on type
        switch (self) {
            .list_pins, .list_signals, .list_params, .list_components, .ping => {},
            .get_pin => |data| {
                try writer.print(",\"name\":\"{s}\"", .{data.name});
            },
            .get_param => |data| {
                try writer.print(",\"name\":\"{s}\"", .{data.name});
            },
            .delete_signal => |data| {
                try writer.print(",\"name\":\"{s}\"", .{data.name});
            },
            .unlink_pin => |data| {
                try writer.print(",\"name\":\"{s}\"", .{data.name});
            },
            .set_pin => |data| {
                try writer.print(",\"name\":\"{s}\",\"value\":", .{data.name});
                try writeHalValue(writer, data.value);
            },
            .set_param => |data| {
                try writer.print(",\"name\":\"{s}\",\"value\":", .{data.name});
                try writeHalValue(writer, data.value);
            },
            .create_signal => |data| {
                try writer.print(",\"name\":\"{s}\",\"pin_type\":\"{s}\"", .{ data.name, @tagName(data.pin_type) });
            },
            .link_pin => |data| {
                try writer.print(",\"pin_name\":\"{s}\",\"sig_name\":\"{s}\"", .{ data.pin_name, data.sig_name });
            },
            .error_response => |data| {
                try writer.print(",\"message\":\"{s}\"", .{data.message});
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
            .allocate = .alloc_always,
        });
        defer parsed.deinit();

        const obj = parsed.value.object;
        const type_str = obj.get("type").?.string;

        const msg_type = MessageType.fromString(type_str) orelse return error.InvalidMessageType;

        return switch (msg_type) {
            .list_pins => blk: {
                const pins_arr = obj.get("pins") orelse return error.InvalidHalValue;
                if (pins_arr != .array) return error.InvalidHalValue;
                var pin_infos = try std.ArrayList(PinInfoResponse).initCapacity(allocator, pins_arr.array.items.len);
                errdefer pin_infos.deinit(allocator);

                for (pins_arr.array.items) |pin_node| {
                    if (pin_node != .object) return error.InvalidHalValue;

                    const name = pin_node.object.get("name") orelse return error.InvalidHalValue;
                    const pin_type_str = pin_node.object.get("type") orelse return error.InvalidHalValue;
                    const dir_str = pin_node.object.get("dir") orelse return error.InvalidHalValue;
                    const val = pin_node.object.get("value") orelse return error.InvalidHalValue;

                    const pin_type = PinType.fromString(pin_type_str.string) orelse return error.InvalidHalType;
                    const pin_dir = if (std.mem.eql(u8, dir_str.string, "in")) backend.PinDir.in
                        else if (std.mem.eql(u8, dir_str.string, "out")) backend.PinDir.out
                        else if (std.mem.eql(u8, dir_str.string, "io")) backend.PinDir.io
                        else return error.InvalidHalDir;

                    try pin_infos.append(allocator, .{
                        .name = try allocator.dupe(u8, name.string),
                        .type = pin_type,
                        .dir = pin_dir,
                        .value = try parseHalValue(&val),
                    });
                }

                break :blk Response{ .list_pins = .{ .pins = try pin_infos.toOwnedSlice(allocator) } };
            },
            .list_signals => blk: {
                const signals_arr = obj.get("signals") orelse return error.InvalidHalValue;
                if (signals_arr != .array) return error.InvalidHalValue;
                var signal_infos = try std.ArrayList(SignalInfoResponse).initCapacity(allocator, signals_arr.array.items.len);
                errdefer signal_infos.deinit(allocator);

                for (signals_arr.array.items) |sig_node| {
                    if (sig_node != .object) return error.InvalidHalValue;

                    const name = sig_node.object.get("name") orelse return error.InvalidHalValue;
                    const sig_type_str = sig_node.object.get("type") orelse return error.InvalidHalValue;
                    const val = sig_node.object.get("value") orelse return error.InvalidHalValue;
                    const writers_arr = sig_node.object.get("writers") orelse return error.InvalidHalValue;
                    const readers_arr = sig_node.object.get("readers") orelse return error.InvalidHalValue;

                    const sig_type = PinType.fromString(sig_type_str.string) orelse return error.InvalidHalType;

                    // Parse writers array
                    var writers = try std.ArrayList([]const u8).initCapacity(allocator, writers_arr.array.items.len);
                    errdefer writers.deinit(allocator);
                    errdefer {
                        for (writers.items) |w| allocator.free(w);
                    }
                    for (writers_arr.array.items) |w_node| {
                        if (w_node != .string) return error.InvalidHalValue;
                        try writers.append(allocator, try allocator.dupe(u8, w_node.string));
                    }

                    // Parse readers array
                    var readers = try std.ArrayList([]const u8).initCapacity(allocator, readers_arr.array.items.len);
                    errdefer readers.deinit(allocator);
                    errdefer {
                        for (readers.items) |r| allocator.free(r);
                    }
                    for (readers_arr.array.items) |r_node| {
                        if (r_node != .string) return error.InvalidHalValue;
                        try readers.append(allocator, try allocator.dupe(u8, r_node.string));
                    }

                    try signal_infos.append(allocator, .{
                        .name = try allocator.dupe(u8, name.string),
                        .type = sig_type,
                        .value = try parseHalValue(&val),
                        .writers = try writers.toOwnedSlice(allocator),
                        .readers = try readers.toOwnedSlice(allocator),
                    });
                }

                break :blk Response{ .list_signals = .{ .signals = try signal_infos.toOwnedSlice(allocator) } };
            },
            .list_params => blk: {
                const params_arr = obj.get("params") orelse return error.InvalidHalValue;
                if (params_arr != .array) return error.InvalidHalValue;
                var param_infos = try std.ArrayList(ParamInfoResponse).initCapacity(allocator, params_arr.array.items.len);
                errdefer param_infos.deinit(allocator);

                for (params_arr.array.items) |param_node| {
                    if (param_node != .object) return error.InvalidHalValue;

                    const name = param_node.object.get("name") orelse return error.InvalidHalValue;
                    const param_type_str = param_node.object.get("type") orelse return error.InvalidHalValue;
                    const dir_str = param_node.object.get("dir") orelse return error.InvalidHalValue;
                    const val = param_node.object.get("value") orelse return error.InvalidHalValue;

                    const param_type = PinType.fromString(param_type_str.string) orelse return error.InvalidHalType;
                    const param_dir = if (std.mem.eql(u8, dir_str.string, "in")) backend.ParamDir.in
                        else if (std.mem.eql(u8, dir_str.string, "out")) backend.ParamDir.out
                        else if (std.mem.eql(u8, dir_str.string, "rw")) backend.ParamDir.rw
                        else return error.InvalidHalDir;

                    try param_infos.append(allocator, .{
                        .name = try allocator.dupe(u8, name.string),
                        .type = param_type,
                        .dir = param_dir,
                        .value = try parseHalValue(&val),
                    });
                }

                break :blk Response{ .list_params = .{ .params = try param_infos.toOwnedSlice(allocator) } };
            },
            .list_components => blk: {
                const comps_arr = obj.get("components") orelse return error.InvalidHalValue;
                if (comps_arr != .array) return error.InvalidHalValue;
                var components = try std.ArrayList([]const u8).initCapacity(allocator, comps_arr.array.items.len);
                errdefer components.deinit(allocator);
                errdefer {
                    for (components.items) |c| allocator.free(c);
                }

                for (comps_arr.array.items) |comp_node| {
                    if (comp_node != .string) return error.InvalidHalValue;
                    try components.append(allocator, try allocator.dupe(u8, comp_node.string));
                }

                break :blk Response{ .list_components = .{ .components = try components.toOwnedSlice(allocator) } };
            },
            .get_pin => blk: {
                const val = obj.get("value") orelse return error.InvalidHalValue;
                break :blk Response{ .get_pin = .{ .value = try parseHalValue(&val) } };
            },
            .set_pin => blk: {
                const val = obj.get("success") orelse return error.InvalidHalValue;
                break :blk Response{ .set_pin = .{ .success = val.bool } };
            },
            .get_param => blk: {
                const val = obj.get("value") orelse return error.InvalidHalValue;
                break :blk Response{ .get_param = .{ .value = try parseHalValue(&val) } };
            },
            .set_param => blk: {
                const val = obj.get("success") orelse return error.InvalidHalValue;
                break :blk Response{ .set_param = .{ .success = val.bool } };
            },
            .create_signal => blk: {
                const val = obj.get("success") orelse return error.InvalidHalValue;
                break :blk Response{ .create_signal = .{ .success = val.bool } };
            },
            .delete_signal => blk: {
                const val = obj.get("success") orelse return error.InvalidHalValue;
                break :blk Response{ .delete_signal = .{ .success = val.bool } };
            },
            .link_pin => blk: {
                const val = obj.get("success") orelse return error.InvalidHalValue;
                break :blk Response{ .link_pin = .{ .success = val.bool } };
            },
            .unlink_pin => blk: {
                const val = obj.get("success") orelse return error.InvalidHalValue;
                break :blk Response{ .unlink_pin = .{ .success = val.bool } };
            },
            .ping => Response{ .ping = .{} },
            .error_response => blk: {
                const val = obj.get("message") orelse return error.InvalidHalValue;
                break :blk Response{ .error_response = .{ .message = val.string } };
            },
        };
    }

    fn parseHalValue(value_node: *const std.json.Value) !HalValue {
        if (value_node.* != .object) return error.InvalidHalValue;
        const obj = &value_node.object;
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
