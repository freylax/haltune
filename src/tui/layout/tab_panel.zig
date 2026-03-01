const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");

pub const TabPanelLayout = struct {
    allocator: std.mem.Allocator,
    mode: Mode,

    pub const Mode = enum {
        full,
        split,
    };

    pub const LayoutResult = struct {
        main: vxfw.Surface,
        plugin: ?vxfw.Surface = null,
    };

    pub fn init(allocator: std.mem.Allocator, mode: Mode) TabPanelLayout {
        return .{
            .allocator = allocator,
            .mode = mode,
        };
    }

    pub fn layout(
        self: *TabPanelLayout,
        ctx: vxfw.DrawContext,
        main_widget: vxfw.Widget,
        plugin_widget: ?vxfw.Widget,
    ) !LayoutResult {
        return switch (self.mode) {
            .full => self.layoutFull(ctx, main_widget),
            .split => self.layoutSplit(ctx, main_widget, plugin_widget),
        };
    }

    fn layoutFull(self: *TabPanelLayout, ctx: vxfw.DrawContext, widget: vxfw.Widget) !LayoutResult {
        _ = self;
        const max = ctx.max.size();

        var surface = try vxfw.Surface.init(
            ctx.arena,
            widget,
            .{ .width = max.width, .height = max.height },
        );

        const base_cell: vaxis.Cell = .{ .default = true };
        @memset(surface.buffer, base_cell);

        if (widget.drawFn) |drawFn| {
            const widget_surface = try drawFn(widget.userdata, ctx);
            for (0..widget_surface.size.height) |y| {
                for (0..widget_surface.size.width) |x| {
                    const cell = widget_surface.buffer[y * widget_surface.size.width + x];
                    if (x < surface.size.width and y < surface.size.height) {
                        surface.buffer[y * surface.size.width + x] = cell;
                    }
                }
            }
        }

        return .{ .main = surface };
    }

    fn layoutSplit(
        self: *TabPanelLayout,
        ctx: vxfw.DrawContext,
        main_widget: vxfw.Widget,
        plugin_widget: ?vxfw.Widget,
    ) !LayoutResult {
        _ = self;
        const max = ctx.max.size();

        const left_width = max.width / 3;
        const right_width = max.width - left_width;

        var main_surface = try vxfw.Surface.init(
            ctx.arena,
            main_widget,
            .{ .width = left_width, .height = max.height },
        );

        const base_cell: vaxis.Cell = .{ .default = true };
        @memset(main_surface.buffer, base_cell);

        const left_ctx = vxfw.DrawContext{
            .arena = ctx.arena,
            .max = .{ .width = left_width, .height = max.height },
        };

        if (main_widget.drawFn) |drawFn| {
            const widget_surface = try drawFn(main_widget.userdata, left_ctx);
            for (0..widget_surface.size.height) |y| {
                for (0..widget_surface.size.width) |x| {
                    const cell = widget_surface.buffer[y * widget_surface.size.width + x];
                    if (x < main_surface.size.width and y < main_surface.size.height) {
                        main_surface.buffer[y * main_surface.size.width + x] = cell;
                    }
                }
            }
        }

        var plugin_surface: ?vxfw.Surface = null;
        if (plugin_widget) |pw| {
            var ps = try vxfw.Surface.init(
                ctx.arena,
                pw,
                .{ .width = right_width, .height = max.height },
            );
            @memset(ps.buffer, base_cell);

            const right_ctx = vxfw.DrawContext{
                .arena = ctx.arena,
                .max = .{ .width = right_width, .height = max.height },
            };

            if (pw.drawFn) |drawFn| {
                const pws = try drawFn(pw.userdata, right_ctx);
                for (0..pws.size.height) |y| {
                    for (0..pws.size.width) |x| {
                        const cell = pws.buffer[y * pws.size.width + x];
                        if (x < ps.size.width and y < ps.size.height) {
                            ps.buffer[y * ps.size.width + x] = cell;
                        }
                    }
                }
            }
            plugin_surface = ps;
        }

        return .{ .main = main_surface, .plugin = plugin_surface };
    }
};
