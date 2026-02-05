const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");
const Model = @import("model.zig").Model;
const ViewMode = @import("model.zig").ViewMode;
const TreeView = @import("widgets/tree_view.zig").TreeView;
const DataTable = @import("widgets/data_table.zig").DataTable;

/// Draw function for conditional single-panel layout
/// Renders either tree view or table view at full width based on current_view
pub fn drawTwoPanelLayout(
    ptr: *anyopaque,
    ctx: vxfw.DrawContext,
) std.mem.Allocator.Error!vxfw.Surface {
    const self: *Model = @ptrCast(@alignCast(ptr));

    // Get maximum available size
    const max = ctx.max.size();

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

    // Render layout based on current view mode
    return switch (self.current_view) {
        .tree_only => {
            // Create full-width tree panel surface
            const tree_surface = try createLeftPanel(self, ctx, max.width, panel_height);

            // Allocate children array (tree + help text)
            const children = try ctx.arena.alloc(vxfw.SubSurface, 2);

            // Tree panel: positioned at origin
            children[0] = .{
                .origin = .{ .row = 0, .col = 0 },
                .surface = tree_surface,
            };

            // Help text at bottom
            const help_text = try createHelpText(ctx, .tree_only);
            children[1] = .{
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
        },
        .table_only => {
            // Create full-width table panel surface
            const table_surface = try createRightPanel(self, ctx, max.width, panel_height);

            // Allocate children array (table + help text)
            const children = try ctx.arena.alloc(vxfw.SubSurface, 2);

            // Table panel: positioned at origin
            children[0] = .{
                .origin = .{ .row = 0, .col = 0 },
                .surface = table_surface,
            };

            // Help text at bottom
            const help_text = try createHelpText(ctx, .table_only);
            children[1] = .{
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
        },
    };
}

/// Create help text widget at bottom of screen
fn createHelpText(ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const help_str = "Enter=Edit/Toggle, /=Search, t=Filter Type, c=Filter Comp, Ctrl+C=Quit";
    const help_style = vaxis.Style{ .dim = true };
    const text_widget = vxfw.Text{ .text = help_str, .style = help_style };

    return try text_widget.widget().draw(ctx);
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
