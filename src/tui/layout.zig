const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const Model = @import("model.zig").Model;
const TreeView = @import("widgets/tree_view.zig").TreeView;
const DataTable = @import("widgets/data_table.zig").DataTable;

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
/// Draws the tree view widget for browsing HAL components
fn createLeftPanel(
    self: *Model,
    ctx: vxfw.DrawContext,
    width: u16,
    height: u16,
) std.mem.Allocator.Error!vxfw.Surface {
    // Constrain drawing to left panel dimensions
    const constrained_ctx = ctx.withConstraints(
        .{ .width = width, .height = height },
        .{ .width = width, .height = height },
    );

    // Draw tree view widget in left panel
    const tree_widget = self.tree_view.widget();
    return try tree_widget.drawFn(tree_widget.userdata, constrained_ctx);
}

/// Create right panel surface (70% width)
/// Draws the data table widget showing checked items
fn createRightPanel(
    self: *Model,
    ctx: vxfw.DrawContext,
    width: u16,
    height: u16,
) std.mem.Allocator.Error!vxfw.Surface {
    // Constrain drawing to right panel dimensions
    const constrained_ctx = ctx.withConstraints(
        .{ .width = width, .height = height },
        .{ .width = width, .height = height },
    );

    // Draw data table widget in right panel
    const table_widget = self.data_table.widget();
    return try table_widget.drawFn(table_widget.userdata, constrained_ctx);
}
