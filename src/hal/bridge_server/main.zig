// HAL Bridge Server
//
// This standalone server exposes HAL functionality over TCP.
// It runs on the LinuxCNC system (pib) and accepts connections from
// haltune clients running on other machines.

const std = @import("std");
const backend = @import("backend");
const HalValue = backend.HalValue;
const native = @import("native");
const protocol = @import("protocol");
const Request = protocol.Request;
const Response = protocol.Response;
const PinType = backend.PinType;

const PORT = 8765;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    std.log.info("HAL Bridge Server starting on port {d}", .{PORT});

    // Create native HAL backend
    var hal_backend = try native.NativeBackend.create(allocator);
    defer hal_backend.deinit();

    // Initialize HAL component
    const comp_id = try hal_backend.initComponent("hal_bridge_server");
    try hal_backend.readyComponent(comp_id);
    std.log.info("HAL component initialized: comp_id={d}", .{comp_id});

    // Start TCP server
    const address = try std.net.Address.parseIp4("0.0.0.0", PORT);
    var listener = try address.listen(.{ .reuse_port = true });
    std.log.info("Listening on {s}:{}", .{ "0.0.0.0", PORT });

    std.log.info("Ready to accept connections", .{});

    // Accept connections
    while (true) {
        const connection = listener.accept() catch |err| {
            std.log.err("Failed to accept connection: {}", .{err});
            continue;
        };

        std.log.info("New connection from {}", .{connection.address});

        // Handle connection in a new thread (or just handle inline for simplicity)
        handleConnection(allocator, hal_backend, connection.stream) catch |err| {
            std.log.err("Connection error: {}", .{err});
        };
    }
}

fn handleConnection(
    allocator: std.mem.Allocator,
    hal_backend: backend.HalBackend,
    stream: std.net.Stream,
) !void {
    defer stream.close();

    const reader = stream.reader();
    var buffer: [4096]u8 = undefined;

    while (true) {
        // Read request line
        const line = reader.readUntilDelimiterAlloc(
            allocator,
            &buffer,
            '\n',
            4096,
        ) catch |err| {
            if (err == error.EndOfStream) {
                std.log.info("Connection closed", .{});
                return;
            }
            std.log.err("Failed to read request: {}", .{err});
            return;
        };

        std.log.debug("Received: {s}", .{line});

        // Parse and handle request
        const response = handleRequest(allocator, hal_backend, line) catch |err| {
            std.log.err("Failed to handle request: {}", .{err});
            // Return error response
            const msg = try std.fmt.allocPrint(allocator, "Error: {}", .{err});
            defer allocator.free(msg);
            try stream.writeAll("{\"type\":\"error\",\"message\":\"");
            try writeJsonEscaped(stream, msg);
            try stream.writeAll("\"}\n");
            continue;
        };

        // Serialize and send response
        const response_json = try responseToJson(allocator, response);
        defer allocator.free(response_json);

        try stream.writeAll(response_json);
        try stream.writeAll("\n");
    }
}

fn handleRequest(
    allocator: std.mem.Allocator,
    hal_backend: backend.HalBackend,
    json_str: []const u8,
) !Response {
    // Parse JSON request
    // For simplicity, just parse the type field
    // A full implementation would use std.json.parseFromSlice

    if (std.mem.indexOf(u8, json_str, "\"type\":\"ping\"")) |_| {
        return Response{ .ping = .{} };
    }

    if (std.mem.indexOf(u8, json_str, "\"type\":\"list_pins\"")) |_| {
        _ = hal_backend.listPins(allocator) catch |err| {
            return Response{ .error_response = .{
                .message = try std.fmt.allocPrint(allocator, "list_pins error: {}", .{err}),
            }};
        };
        // Convert to response format
        // TODO: implement conversion
        return Response{ .list_pins = .{ .pins = &.{} } };
    }

    if (std.mem.indexOf(u8, json_str, "\"type\":\"get_pin\"")) |_| {
        // Parse name from JSON
        const name_start = std.mem.indexOf(u8, json_str, "\"name\":\"").? + 8;
        const name_end = std.mem.indexOf(u8, json_str[name_start..], "\"").? + name_start;
        const name = json_str[name_start..name_end];

        const value = try hal_backend.getPinValue(name);
        return Response{ .get_pin = .{ .value = value } };
    }

    if (std.mem.indexOf(u8, json_str, "\"type\":\"set_pin\"")) |_| {
        // Parse name and value
        const name_start = std.mem.indexOf(u8, json_str, "\"name\":\"").? + 8;
        const name_end = std.mem.indexOf(u8, json_str[name_start..], "\"").? + name_start;
        const name = json_str[name_start..name_end];

        // Parse value (simplified)
        const value: HalValue = .{ .bit = false }; // TODO: parse properly
        try hal_backend.setPinValue(name, value);
        return Response{ .set_pin = .{ .success = true } };
    }

    return Response{ .error_response = .{ .message = "Unknown request type" } };
}

fn responseToJson(allocator: std.mem.Allocator, resp: Response) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    const writer = buffer.writer();

    try writer.writeAll("{\"type\":\"");

    switch (resp) {
        .ping => {
            try writer.writeAll("ping\"}");
        },
        .get_pin => |*r| {
            try writer.writeAll("get_pin\",\"value\":");
            try writeHalValue(writer, r.value);
            try writer.writeAll("}");
        },
        .set_pin => |*r| {
            try writer.print("set_pin\",\"success\":{}}}", .{r.success});
        },
        .list_pins => |*r| {
            _ = r;
            try writer.writeAll("list_pins\",\"pins\":[]}");
        },
        else => {
            try writer.writeAll("error\"}");
        },
    }

    return buffer.toOwnedSlice();
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

fn writeJsonEscaped(stream: std.net.Stream, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\' => try stream.writeAll("\\\\"),
            '"' => try stream.writeAll("\\\""),
            '\n' => try stream.writeAll("\\n"),
            '\r' => try stream.writeAll("\\r"),
            '\t' => try stream.writeAll("\\t"),
            else => try stream.writeAll(&.{c}),
        }
    }
}
