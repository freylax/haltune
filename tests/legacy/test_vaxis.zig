// Simple vxfw test to verify TUI works
const std = @import("std");
const vxfw = @import("vaxis").vxfw;

const SimpleWidget = struct {
    text: []const u8,

    pub fn widget(self: *SimpleWidget) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = typeErasedEventHandler,
            .drawFn = typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        _ = ptr;
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }
            },
            else => {},
        }
    }

    fn typeErasedDrawFn(
        ptr: *anyopaque,
        ctx: vxfw.DrawContext,
    ) std.mem.Allocator.Error!vxfw.Surface {
        const self: *SimpleWidget = @ptrCast(@alignCast(ptr));

        const text_widget = vxfw.Text{ .text = self.text };
        const text_surface = try text_widget.widget().draw(ctx);

        return .{
            .size = text_surface.size,
            .widget = self.widget(),
            .buffer = &.{},
            .children = &.{.{
                .origin = .{ .row = 0, .col = 0 },
                .surface = text_surface,
            }},
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var simple_widget = SimpleWidget{ .text = "Hello! Press Ctrl+C to quit." };

    var app = try vxfw.App.init(allocator);
    defer app.deinit();

    try app.run(simple_widget.widget(), .{});
}
