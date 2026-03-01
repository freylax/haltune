#!/bin/bash
# Fix for union field access panic in hal_protocol.zig
# Run this on pib where LinuxCNC is installed

cd ~/prog/haltune

# Apply the fix to parseHalValue - use switch instead of if-chain
cat > /tmp/parse_hal_value_fix.zig << 'EOF'
    fn parseHalValue(value_node: *const std.json.Value) !HalValue {
        if (value_node.* != .object) return error.InvalidHalValue;
        const obj = &value_node.object;
        if (obj.get("bit")) |v| {
            if (v != .bool) return error.InvalidHalValue;
            return HalValue{ .bit = v.bool };
        }
        if (obj.get("float")) |v| {
            // Accept both integer and float types for float values
            // Bridge server may send {"float":0} which parser interprets as integer
            switch (v) {
                .float => |f| return HalValue{ .float = f },
                .integer => |i| return HalValue{ .float = @floatFromInt(i) },
                else => {
                    std.log.err("parseHalValue: invalid 'float' value type: {}", .{@tagName(v)});
                    return error.InvalidHalValue;
                },
            }
        }
        if (obj.get("s32")) |v| {
            if (v != .integer) return error.InvalidHalValue;
            return HalValue{ .s32 = @intCast(v.integer) };
        }
        if (obj.get("u32")) |v| {
            if (v != .integer) return error.InvalidHalValue;
            return HalValue{ .u32 = @intCast(v.integer) };
        }
        return error.InvalidHalValue;
    }
EOF

# Backup and patch
cp src/hal_protocol.zig src/hal_protocol.zig.bak

# Use sed to replace the parseHalValue function
# This is a bit complex, so let's use Python
python3 << 'PYTHON_EOF'
import sys

with open('src/hal_protocol.zig', 'r') as f:
    content = f.read()

# Find and replace the parseHalValue function
old_func = '''    fn parseHalValue(value_node: *const std.json.Value) !HalValue {
        if (value_node.* != .object) return error.InvalidHalValue;
        const obj = &value_node.object;
        if (obj.get("bit")) |v| {
            if (v != .bool) return error.InvalidHalValue;
            return HalValue{ .bit = v.bool };
        }
        if (obj.get("float")) |v| {
            // Accept both integer and float types for float values
            // Bridge server may send {"float":0} which parser interprets as integer
            if (v == .float) {
                return HalValue{ .float = v.float };
            } else if (v == .integer) {
                return HalValue{ .float = @floatFromInt(v.integer) };
            } else {
                return error.InvalidHalValue;
            }
        }
        if (obj.get("s32")) |v| {
            if (v != .integer) return error.InvalidHalValue;
            return HalValue{ .s32 = @intCast(v.integer) };
        }
        if (obj.get("u32")) |v| {
            if (v != .integer) return error.InvalidHalValue;
            return HalValue{ .u32 = @intCast(v.integer) };
        }
        return error.InvalidHalValue;
    }'''

new_func = '''    fn parseHalValue(value_node: *const std.json.Value) !HalValue {
        if (value_node.* != .object) return error.InvalidHalValue;
        const obj = &value_node.object;
        if (obj.get("bit")) |v| {
            if (v != .bool) return error.InvalidHalValue;
            return HalValue{ .bit = v.bool };
        }
        if (obj.get("float")) |v| {
            // Accept both integer and float types for float values
            // Bridge server may send {"float":0} which parser interprets as integer
            switch (v) {
                .float => |f| return HalValue{ .float = f },
                .integer => |i| return HalValue{ .float = @floatFromInt(i) },
                else => {
                    std.log.err("parseHalValue: invalid 'float' value type: {}", .{@tagName(v)});
                    return error.InvalidHalValue;
                },
            }
        }
        if (obj.get("s32")) |v| {
            if (v != .integer) return error.InvalidHalValue;
            return HalValue{ .s32 = @intCast(v.integer) };
        }
        if (obj.get("u32")) |v| {
            if (v != .integer) return error.InvalidHalValue;
            return HalValue{ .u32 = @intCast(v.integer) };
        }
        return error.InvalidHalValue;
    }'''

if old_func in content:
    content = content.replace(old_func, new_func)
    with open('src/hal_protocol.zig', 'w') as f:
        f.write(content)
    print("Successfully patched src/hal_protocol.zig")
else:
    print("Could not find parseHalValue function - may already be patched or different version")
    sys.exit(1)
PYTHON_EOF

if [ $? -eq 0 ]; then
    echo "Patch applied successfully. Rebuilding..."
    zig build
    if [ $? -eq 0 ]; then
        echo "Build successful! Now test with:"
        echo "  1. Start hal_bridge_server on pib"
        echo "  2. Run: zig-out/bin/haltune"
    else
        echo "Build failed. Restoring backup..."
        mv src/hal_protocol.zig.bak src/hal_protocol.zig
    fi
else
    echo "Patch failed. Keeping original file."
fi
