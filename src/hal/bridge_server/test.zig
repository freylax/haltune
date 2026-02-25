//! HAL Bridge Server Unit Tests
//!
//! Tests for bridge server protocol and response handling.

const std = @import("std");
const backend = @import("backend");
const protocol = @import("protocol");

test "Protocol - ping request serialization" {
    const req = protocol.Request{ .ping = .{} };
    const json = try req.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings("{\"type\":\"ping\"}", json);
    std.debug.print("OK: Serialized ping: {s}\n", .{json});
}

test "Protocol - get_pin request serialization" {
    const req = protocol.Request{ .get_pin = .{ .name = "motion.enable-pin" } };
    const json = try req.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "get_pin") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "motion.enable-pin") != null);
    std.debug.print("OK: Serialized get_pin: {s}\n", .{json});
}

test "Protocol - list_pins request serialization" {
    const req = protocol.Request{ .list_pins = .{} };
    const json = try req.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "list_pins") != null);
    std.debug.print("OK: Serialized list_pins: {s}\n", .{json});
}

test "Protocol - set_pin request serialization" {
    const req = protocol.Request{ .set_pin = .{
        .name = "test.pin",
        .value = .{ .bit = true },
    }};
    const json = try req.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "set_pin") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "test.pin") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "bit") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "true") != null);
    std.debug.print("OK: Serialized set_pin: {s}\n", .{json});
}

test "Protocol - Response from JSON - ping" {
    const json = "{\"type\":\"ping\"}";
    const resp = try protocol.Response.fromJson(std.testing.allocator, json);

    try std.testing.expectEqual(protocol.MessageType.ping, std.meta.activeTag(resp));
    std.debug.print("OK: Parsed ping response\n", .{});
}

test "Protocol - Response from JSON - get_pin with bit value" {
    const json = "{\"type\":\"get_pin\",\"value\":{\"bit\":true}}";
    const resp = try protocol.Response.fromJson(std.testing.allocator, json);

    try std.testing.expectEqual(protocol.MessageType.get_pin, std.meta.activeTag(resp));
    switch (resp) {
        .get_pin => |r| try std.testing.expect(r.value.bit == true),
        else => try std.testing.expect(false),
    }
    std.debug.print("OK: Parsed get_pin response with bit=true\n", .{});
}

test "Protocol - Response from JSON - get_pin with float value" {
    const json = "{\"type\":\"get_pin\",\"value\":{\"float\":3.14}}";
    const resp = try protocol.Response.fromJson(std.testing.allocator, json);

    try std.testing.expectEqual(protocol.MessageType.get_pin, std.meta.activeTag(resp));
    switch (resp) {
        .get_pin => |r| {
            try std.testing.expect(r.value.float == 3.14);
        },
        else => try std.testing.expect(false),
    }
    std.debug.print("OK: Parsed get_pin response with float=3.14\n", .{});
}

test "Protocol - Response from JSON - set_pin success" {
    const json = "{\"type\":\"set_pin\",\"success\":true}";
    const resp = try protocol.Response.fromJson(std.testing.allocator, json);

    try std.testing.expectEqual(protocol.MessageType.set_pin, std.meta.activeTag(resp));
    switch (resp) {
        .set_pin => |r| try std.testing.expect(r.success == true),
        else => try std.testing.expect(false),
    }
    std.debug.print("OK: Parsed set_pin response with success=true\n", .{});
}

test "Protocol - Response from JSON - error" {
    const json = "{\"type\":\"error\",\"message\":\"Test error\"}";
    const resp = try protocol.Response.fromJson(std.testing.allocator, json);

    try std.testing.expectEqual(protocol.MessageType.error_response, std.meta.activeTag(resp));
    switch (resp) {
        .error_response => |r| {
            try std.testing.expectEqualStrings("Test error", r.message);
        },
        else => try std.testing.expect(false),
    }
    std.debug.print("OK: Parsed error response\n", .{});
}
