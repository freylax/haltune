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

    // TODO: Draw save dialog if visible
    // Draw centered modal box with filename input
    if (self.save_dialog_visible) {
        // Placeholder: save dialog overlay will be drawn here
        // For now, the dialog state is managed but not rendered
        // Full implementation requires drawing:
        // - Centered modal box
        // - "Save Configuration" title
        // - Current filename input field
        // - Instructions: "Enter to save, Escape to cancel"
        // - Error message if present
    }

    // Reserve one row at bottom for help text
    const help_height: u16 = 1;
    const panel_height = if (max.height > help_height) max.height - help_height else max.height;

    // Calculate panel sizes: 30% left, 70% right
    const left_width = max.width / 3;
    const right_width = max.width - left_width;

    // Create left panel surface (tree navigation area)
    const left_surface = try createLeftPanel(self, ctx, left_width, panel_height);

    // Create right panel surface (data table area)
    const right_surface = try createRightPanel(self, ctx, right_width, panel_height);

    // Allocate children array in arena (panels + help text)
    const children = try ctx.arena.alloc(vxfw.SubSurface, 3);

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

    // Help text at bottom
    const help_text = try createHelpText(ctx);
    children[2] = .{
        .origin = .{ .row = panel_height, .col = 0 },
        .surface = help_text,
    };

    // Return the root surface with children
    return .{
        .size = max,
        .widget = self.widget(),
        .buffer = &.{},
        .children = children,
    };
}

/// Create help text widget at bottom of screen
fn createHelpText(ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const help_str = "Enter=Edit/Toggle, /=Search, t=Filter Type, c=Filter Comp, Ctrl+C=Quit";
    const help_style = vxfw.Style{ .dim = true };
    const help_widget = vxfw.Text.asWidget(help_str, .{ .style = help_style });

    return try help_widget.draw(ctx);
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
