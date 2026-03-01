// PluginContainer - Wraps plugin render with border and title
const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");

pub const PluginContainer = struct {
    allocator: std.mem.Allocator,
    title: []const u8,
    plugin_widget: vxfw.Widget,

    pub fn init(allocator: std.mem.Allocator, title: []const u8, plugin_widget: vxfw.Widget) PluginContainer {
        return .{
            .allocator = allocator,
            .title = title,
            .plugin_widget = plugin_widget,
        };
    }

    pub fn widget(self: *PluginContainer) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = struct {
                fn handler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) !void {
                    const pc: *PluginContainer = @ptrCast(@alignCast(ptr));
                    if (pc.plugin_widget.eventHandler) |eh| {
                        try eh(pc.plugin_widget.userdata, ctx, event);
                    }
                }
            }.handler,
            .drawFn = struct {
                fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
                    const pc: *PluginContainer = @ptrCast(@alignCast(ptr));
                    return pc.draw(ctx);
                }
            }.draw,
        };
    }

    pub fn draw(self: *PluginContainer, ctx: vxfw.DrawContext) !vxfw.Surface {
        const max_size = ctx.max.size();
        const width = @min(max_size.width, 80);
        const height = @min(max_size.height, 20);

        var surface = try vxfw.Surface.init(
            ctx.arena,
            self.widget(),
            .{ .width = @intCast(width), .height = @intCast(height) },
        );

        const base_cell: vaxis.Cell = .{ .default = true };
        @memset(surface.buffer, base_cell);

        // Draw border box
        for (0..width) |i| {
            surface.writeCell(@intCast(i), 0, .{ .char = .{ .grapheme = "-", .width = 1 }, .style = .{ .dim = true } });
            surface.writeCell(@intCast(i), height - 1, .{ .char = .{ .grapheme = "-", .width = 1 }, .style = .{ .dim = true } });
        }
        for (1..height - 1) |i| {
            surface.writeCell(0, @intCast(i), .{ .char = .{ .grapheme = "|", .width = 1 }, .style = .{ .dim = true } });
            surface.writeCell(width - 1, @intCast(i), .{ .char = .{ .grapheme = "|", .width = 1 }, .style = .{ .dim = true } });
        }

        // Draw title in top border
        const title_start = @as(usize, @intCast((width - self.title.len) / 2));
        for (self.title, 0..) |c, i| {
            if (title_start + i < width) {
                surface.writeCell(@intCast(title_start + i), 0, .{
                    .char = .{ .grapheme = &[1]u8{c}, .width = 1 },
                    .style = .{ .bold = true },
                });
            }
        }

        // Draw plugin widget in inner area
        if (self.plugin_widget.drawFn) |drawFn| {
            if (width > 2 and height > 2) {
                const plugin_ctx = vxfw.DrawContext{
                    .arena = ctx.arena,
                    .max = .{ .width = width - 2, .height = height - 2 },
                };
                const plugin_surface = try drawFn(self.plugin_widget.userdata, plugin_ctx);

                for (0..plugin_surface.size.height) |y| {
                    for (0..plugin_surface.size.width) |x| {
                        const cell = plugin_surface.buffer[y * plugin_surface.size.width + x];
                        if (x + 1 < width - 1 and y + 1 < height - 1) {
                            surface.writeCell(@intCast(x + 1), @intCast(y + 1), cell);
                        }
                    }
                }
            }
        }

        return surface;
    }
};
