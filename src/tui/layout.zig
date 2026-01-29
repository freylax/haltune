const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const Model = @import("model.zig").Model;

/// Draw function for two-panel split layout
/// Left panel: 30% of screen width (tree navigation)
/// Right panel: 70% of screen width (data table)
pub fn drawTwoPanelLayout(
    ptr: *anyopaque,
    ctx: vxfw.DrawContext,
) std.mem.Allocator.Error!vxfw.Surface {
    const self: *Model = @ptrCast(@alignCast(ptr));

    // Get maximum available size
    const max = ctx.max.size() orelse .{ .width = 80, .height = 24 };

    // Calculate panel sizes: 30% left, 70% right
    const left_width = max.width / 3;
    const right_width = max.width - left_width;

    // Create left panel surface (tree navigation area)
    const left_surface = try createLeftPanel(self, ctx, left_width, max.height);

    // Create right panel surface (data table area)
    const right_surface = try createRightPanel(self, ctx, right_width, max.height);

    // Allocate children array in arena
    const children = try ctx.arena.alloc(vxfw.SubSurface, 2);

    // Left panel: positioned at origin
    children[0] = .{
        .origin = .{ .row = 0, .col = 0 },
        .surface = left_surface,
    };

    // Right panel: positioned after left panel
    children[1] = .{
        .origin = .{ .row = 0, .col = left_width },
        .surface = right_surface,
    };

    // Return the root surface with two children
    return .{
        .size = max,
        .widget = self.widget(),
        .buffer = &.{},
        .children = children,
    };
}

/// Create left panel surface (30% width)
/// Placeholder for tree view widget (will implement in plan 03-02)
fn createLeftPanel(
    self: *Model,
    ctx: vxfw.DrawContext,
    width: u16,
    height: u16,
) std.mem.Allocator.Error!vxfw.Surface {
    _ = self;

    // Constrain drawing to left panel dimensions
    const constrained_ctx = ctx.withConstraints(
        .{ .width = width, .height = height },
        .{ .width = width, .height = height },
    );

    // Placeholder surface - empty buffer, no children
    // In plan 03-02, this will draw the tree view widget
    return .{
        .size = .{ .width = width, .height = height },
        .widget = undefined,
        .buffer = &.{},
        .children = &.{},
    };
}

/// Create right panel surface (70% width)
/// Placeholder for data table widget (will implement in plan 03-03)
fn createRightPanel(
    self: *Model,
    ctx: vxfw.DrawContext,
    width: u16,
    height: u16,
) std.mem.Allocator.Error!vxfw.Surface {
    _ = self;

    // Constrain drawing to right panel dimensions
    const constrained_ctx = ctx.withConstraints(
        .{ .width = width, .height = height },
        .{ .width = width, .height = height },
    );

    _ = constrained_ctx; // Will use in plan 03-03

    // Placeholder surface - empty buffer, no children
    // In plan 03-03, this will draw the data table widget
    return .{
        .size = .{ .width = width, .height = height },
        .widget = undefined,
        .buffer = &.{},
        .children = &.{},
    };
}
