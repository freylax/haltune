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
    var listener = try address.listen(.{ .reuse_address = true });
    std.log.info("Listening on {s}:{}", .{ "0.0.0.0", PORT });

    std.log.info("Ready to accept connections", .{});

    // Accept connections
    while (true) {
        const connection = listener.accept() catch |err| {
            std.log.err("Failed to accept connection: {}", .{err});
            continue;
        };

        std.log.info("New connection from {any}", .{connection.address});

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

    var read_buffer: [4096]u8 = undefined;

    while (true) {
        // Read request line
        const line = readLine(stream, &read_buffer) catch |err| {
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
        std.log.debug("Sending response...", .{});
        const response_json = responseToJson(allocator, response) catch |err| {
            std.log.err("responseToJson failed: {}", .{err});
            return err;
        };
        defer allocator.free(response_json);

        std.log.info("Sending JSON response (len={d}): {s}", .{response_json.len, response_json[0..@min(response_json.len, 100)]});
        stream.writeAll(response_json) catch |err| {
            std.log.err("writeAll failed for response_json: {}", .{err});
            return err;
        };
        stream.writeAll("\n") catch |err| {
            std.log.err("writeAll failed for newline: {}", .{err});
            return err;
        };
        std.log.debug("Response sent successfully", .{});
    }
}

/// Read a line (up to \n) from stream
fn readLine(stream: std.net.Stream, buffer: []u8) ![]const u8 {
    var index: usize = 0;
    while (index < buffer.len - 1) {
        var byte_buf: [1]u8 = undefined;
        const bytes_read = try stream.read(&byte_buf);
        if (bytes_read == 0) {
            if (index > 0) break; // End of input but we have data
            return error.EndOfStream;
        }
        const byte = byte_buf[0];
        if (byte == '\n') break;
        buffer[index] = byte;
        index += 1;
    }
    return buffer[0..index];
}

fn handleRequest(
    allocator: std.mem.Allocator,
    hal_backend: backend.HalBackend,
    json_str: []const u8,
) !Response {
    // First, try to determine the request type from the JSON
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{
        .allocate = .alloc_always,
    }) catch |err| {
        std.log.err("JSON parse error: {}", .{err});
        return Response{ .error_response = .{ .message = "Invalid JSON" } };
    };
    defer parsed.deinit();

    const obj = parsed.value.object;
    const type_str = obj.get("type") orelse return Response{ .error_response = .{ .message = "Missing type field" } };

    const msg_type = protocol.MessageType.fromString(type_str.string) orelse {
        return Response{ .error_response = .{ .message = "Unknown request type" } };
    };

    // Now handle each request type
    switch (msg_type) {
        .ping => return Response{ .ping = .{} },

        .list_pins => {
            std.log.info("list_pins: Starting to list pins", .{});
            const pins = hal_backend.listPins(allocator) catch |err| {
                std.log.err("list_pins: listPins failed with error: {}", .{err});
                return Response{ .error_response = .{
                    .message = try std.fmt.allocPrint(allocator, "list_pins error: {}", .{err}),
                }};
            };
            std.log.info("list_pins: Found {d} pins", .{pins.len});
            defer {
                for (pins) |p| allocator.free(p.name);
                allocator.free(pins);
            }

            // Convert to protocol response format
            var pin_infos = try std.ArrayList(protocol.Response.PinInfoResponse).initCapacity(allocator, pins.len);
            errdefer pin_infos.deinit(allocator);

            for (pins) |pin| {
                try pin_infos.append(allocator, .{
                    .name = try allocator.dupe(u8, pin.name),
                    .type = pin.type,
                    .dir = pin.dir,
                    .value = pin.value,
                });
            }

            std.log.info("list_pins: Returning {d} pin_infos", .{pin_infos.items.len});
            return Response{ .list_pins = .{ .pins = try pin_infos.toOwnedSlice(allocator) } };
        },

        .get_pin => {
            const name_node = obj.get("name") orelse return Response{ .error_response = .{ .message = "Missing name field" } };
            const name = name_node.string;

            const value = try hal_backend.getPinValue(name);
            return Response{ .get_pin = .{ .value = value } };
        },

        .set_pin => {
            const name_node = obj.get("name") orelse return Response{ .error_response = .{ .message = "Missing name field" } };
            const name = name_node.string;

            const value_node = obj.get("value") orelse return Response{ .error_response = .{ .message = "Missing value field" } };
            const value = try parseHalValue(&value_node);

            // For remote HAL, setPinValue may fail if the pin doesn't exist
            // This is OK - plugins may set pins that don't exist yet
            hal_backend.setPinValue(name, value) catch |err| {
                std.log.warn("setPinValue failed for '{s}': {} (continuing anyway)", .{name, err});
            };
            return Response{ .set_pin = .{ .success = true } };
        },

        .list_signals => {
            const signals = hal_backend.listSignals(allocator) catch |err| {
                return Response{ .error_response = .{
                    .message = try std.fmt.allocPrint(allocator, "list_signals error: {}", .{err}),
                }};
            };
            defer {
                for (signals) |s| {
                    allocator.free(s.name);
                    allocator.free(s.writers);
                    allocator.free(s.readers);
                }
                allocator.free(signals);
            }

            var signal_infos = try std.ArrayList(protocol.Response.SignalInfoResponse).initCapacity(allocator, signals.len);
            errdefer signal_infos.deinit(allocator);

            for (signals) |sig| {
                try signal_infos.append(allocator, .{
                    .name = try allocator.dupe(u8, sig.name),
                    .type = sig.type,
                    .value = sig.value,
                    .writers = sig.writers,
                    .readers = sig.readers,
                });
            }

            return Response{ .list_signals = .{ .signals = try signal_infos.toOwnedSlice(allocator) } };
        },

        .list_params => {
            const params = hal_backend.listParams(allocator) catch |err| {
                return Response{ .error_response = .{
                    .message = try std.fmt.allocPrint(allocator, "list_params error: {}", .{err}),
                }};
            };
            defer {
                for (params) |p| allocator.free(p.name);
                allocator.free(params);
            }

            var param_infos = try std.ArrayList(protocol.Response.ParamInfoResponse).initCapacity(allocator, params.len);
            errdefer param_infos.deinit(allocator);

            for (params) |param| {
                try param_infos.append(allocator, .{
                    .name = try allocator.dupe(u8, param.name),
                    .type = param.type,
                    .dir = param.dir,
                    .value = param.value,
                });
            }

            return Response{ .list_params = .{ .params = try param_infos.toOwnedSlice(allocator) } };
        },

        .list_components => {
            const components = hal_backend.listComponents(allocator) catch |err| {
                return Response{ .error_response = .{
                    .message = try std.fmt.allocPrint(allocator, "list_components error: {}", .{err}),
                }};
            };
            defer {
                for (components) |c| allocator.free(c);
                allocator.free(components);
            }

            // Make copies for protocol response
            var component_copies = try std.ArrayList([]const u8).initCapacity(allocator, components.len);
            errdefer component_copies.deinit(allocator);
            errdefer {
                for (component_copies.items) |c| allocator.free(c);
            }

            for (components) |comp| {
                try component_copies.append(allocator, try allocator.dupe(u8, comp));
            }

            return Response{ .list_components = .{ .components = try component_copies.toOwnedSlice(allocator) } };
        },

        .get_param => {
            const name_node = obj.get("name") orelse return Response{ .error_response = .{ .message = "Missing name field" } };
            const name = name_node.string;

            const value = try hal_backend.getParamValue(name);
            return Response{ .get_param = .{ .value = value } };
        },

        .set_param => {
            const name_node = obj.get("name") orelse return Response{ .error_response = .{ .message = "Missing name field" } };
            const name = name_node.string;

            const value_node = obj.get("value") orelse return Response{ .error_response = .{ .message = "Missing value field" } };
            const value = try parseHalValue(&value_node);

            try hal_backend.setParamValue(name, value);
            return Response{ .set_param = .{ .success = true } };
        },

        .create_signal => {
            const name_node = obj.get("name") orelse return Response{ .error_response = .{ .message = "Missing name field" } };
            const name = name_node.string;

            const type_node = obj.get("pin_type") orelse return Response{ .error_response = .{ .message = "Missing pin_type field" } };
            const pin_type_str = type_node.string;
            const pin_type = PinType.fromString(pin_type_str) orelse return Response{ .error_response = .{ .message = "Invalid pin type" } };

            // Try to delete the signal first if it exists (ignore errors)
            hal_backend.deleteSignal(name) catch |err| {
                std.log.debug("deleteSignal before create failed: {}", .{err});
            };

            try hal_backend.createSignal(name, pin_type);
            return Response{ .create_signal = .{ .success = true } };
        },

        .delete_signal => {
            const name_node = obj.get("name") orelse return Response{ .error_response = .{ .message = "Missing name field" } };
            const name = name_node.string;

            try hal_backend.deleteSignal(name);
            return Response{ .delete_signal = .{ .success = true } };
        },

        .link_pin => {
            const pin_name_node = obj.get("pin_name") orelse return Response{ .error_response = .{ .message = "Missing pin_name field" } };
            const pin_name = pin_name_node.string;

            const sig_name_node = obj.get("sig_name") orelse return Response{ .error_response = .{ .message = "Missing sig_name field" } };
            const sig_name = sig_name_node.string;

            // For remote HAL, linkPin may fail if the pin doesn't exist
            // This is OK - the signal was created, and other components can link to it
            hal_backend.linkPin(pin_name, sig_name) catch |err| {
                std.log.warn("linkPin failed for '{s}' -> '{s}': {} (signal exists, continuing)", .{pin_name, sig_name, err});
            };
            return Response{ .link_pin = .{ .success = true } };
        },

        .unlink_pin => {
            const name_node = obj.get("name") orelse return Response{ .error_response = .{ .message = "Missing name field" } };
            const name = name_node.string;

            try hal_backend.unlinkPin(name);
            return Response{ .unlink_pin = .{ .success = true } };
        },

        .error_response => return Response{ .error_response = .{ .message = "Unexpected error_response from client" } },
    }
}

/// Parse HalValue from JSON node
fn parseHalValue(value_node: *const std.json.Value) !HalValue {
    if (value_node.* != .object) return error.InvalidHalValue;

    const obj = &value_node.object;
    if (obj.get("bit")) |*v| {
        return HalValue{ .bit = v.bool };
    }
    if (obj.get("float")) |*v| {
        // JSON parser may treat numbers as integers, convert appropriately
        if (v.* == .float) {
            return HalValue{ .float = v.float };
        } else if (v.* == .integer) {
            return HalValue{ .float = @floatFromInt(v.integer) };
        } else {
            return error.InvalidHalValue;
        }
    }
    if (obj.get("s32")) |*v| {
        return HalValue{ .s32 = @intCast(v.integer) };
    }
    if (obj.get("u32")) |*v| {
        return HalValue{ .u32 = @intCast(v.integer) };
    }
    return error.InvalidHalValue;
}

fn responseToJson(allocator: std.mem.Allocator, resp: Response) ![]const u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

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
            try writer.writeAll("list_pins\",\"pins\":[");
            for (r.pins, 0..) |pin, i| {
                if (i > 0) try writer.writeAll(",");
                try writer.print("{{\"name\":\"{s}\",\"type\":\"{s}\",\"dir\":\"{s}\",\"value\":", .{ pin.name, @tagName(pin.type), pinDirToString(pin.dir) });
                try writeHalValue(writer, pin.value);
                try writer.writeAll("}");  // Close pin object (writeHalValue already closed value)
            }
            try writer.writeAll("]}");
        },
        .list_signals => |*r| {
            try writer.writeAll("list_signals\",\"signals\":[");
            for (r.signals, 0..) |sig, i| {
                if (i > 0) try writer.writeAll(",");
                try writer.print("{{\"name\":\"{s}\",\"type\":\"{s}\",\"value\":", .{ sig.name, @tagName(sig.type) });
                try writeHalValue(writer, sig.value);
                try writer.writeAll(",\"writers\":[");
                for (sig.writers, 0..) |w, j| {
                    if (j > 0) try writer.writeAll(",");
                    try writer.print("\"{s}\"", .{w});
                }
                try writer.writeAll("],\"readers\":[");
                for (sig.readers, 0..) |reader, j| {
                    if (j > 0) try writer.writeAll(",");
                    try writer.print("\"{s}\"", .{reader});
                }
                try writer.writeAll("]}");
            }
            try writer.writeAll("]}");
        },
        .list_params => |*r| {
            try writer.writeAll("list_params\",\"params\":[");
            for (r.params, 0..) |param, i| {
                if (i > 0) try writer.writeAll(",");
                try writer.print("{{\"name\":\"{s}\",\"type\":\"{s}\",\"dir\":\"{s}\",\"value\":", .{ param.name, @tagName(param.type), paramDirToString(param.dir) });
                try writeHalValue(writer, param.value);
                try writer.writeAll("}");  // Close param object (writeHalValue already closed value)
            }
            try writer.writeAll("]}");
        },
        .list_components => |*r| {
            try writer.writeAll("list_components\",\"components\":[");
            for (r.components, 0..) |comp, i| {
                if (i > 0) try writer.writeAll(",");
                try writer.print("\"{s}\"", .{comp});
            }
            try writer.writeAll("]}");
        },
        .get_param => |*r| {
            try writer.writeAll("get_param\",\"value\":");
            try writeHalValue(writer, r.value);
            try writer.writeAll("}");
        },
        .set_param => |*r| {
            try writer.print("set_param\",\"success\":{}}}", .{r.success});
        },
        .create_signal => |*r| {
            try writer.print("create_signal\",\"success\":{}}}", .{r.success});
        },
        .delete_signal => |*r| {
            try writer.print("delete_signal\",\"success\":{}}}", .{r.success});
        },
        .link_pin => |*r| {
            try writer.print("link_pin\",\"success\":{}}}", .{r.success});
        },
        .unlink_pin => |*r| {
            try writer.print("unlink_pin\",\"success\":{}}}", .{r.success});
        },
        .error_response => |*r| {
            try writer.writeAll("error\",\"message\":\"");
            try writeJsonEscapedWriter(writer, r.message);
            try writer.writeAll("\"}");
        },
    }

    return buffer.toOwnedSlice(allocator);
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

fn pinDirToString(dir: backend.PinDir) []const u8 {
    return switch (dir) {
        .in => "in",
        .out => "out",
        .io => "io",
    };
}

fn paramDirToString(dir: backend.ParamDir) []const u8 {
    return switch (dir) {
        .in => "in",
        .out => "out",
        .rw => "rw",
    };
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

fn writeJsonEscapedWriter(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeAll(&.{c}),
        }
    }
}
