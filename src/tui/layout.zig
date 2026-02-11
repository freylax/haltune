const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");
const Model = @import("model.zig").Model;
const ViewMode = @import("model.zig").ViewMode;
const TreeView = @import("widgets/tree_view.zig").TreeView;
const DataTable = @import("widgets/data_table.zig").DataTable;
const ItemType = @import("widgets/data_table.zig").ItemType;
const TreeNode = @import("widgets/tree_view.zig").Node;

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
            const help_text = try createHelpText(ctx, .tree_only, self);
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
            const help_text = try createHelpText(ctx, .table_only, self);
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

/// Create help text widget at bottom of screen with dynamic view mode hint
fn createHelpText(ctx: vxfw.DrawContext, view_mode: ViewMode, model: *const Model) std.mem.Allocator.Error!vxfw.Surface {
    // Get cursor value for status line (left side)
    const cursor_value_text = blk: {
        if (view_mode == .tree_only) {
            // Tree mode
            if (model.tree_view.isEditMode()) {
                // Show edit mode status
                if (model.tree_view.edit_mode) {
                    break :blk try std.fmt.allocPrint(ctx.arena, "Editing: {s}", .{model.tree_view.edit_buffer.items});
                } else if (model.tree_view.signal_edit_mode) {
                    break :blk try std.fmt.allocPrint(ctx.arena, "Signal: {s}", .{model.tree_view.signal_edit_buffer.items});
                } else if (model.tree_view.signal_delete_prompt) {
                    break :blk try std.fmt.allocPrint(ctx.arena, "Delete signal? (y/n)", .{});
                }
            } else if (model.tree_view.getCursorNode()) |node| {
                // Show cursor item value
                const item_type: ItemType = switch (node.item_type) {
                    .pin => .pin,
                    .signal => .signal,
                    .param => .param,
                    .component => break :blk "",
                };
                break :blk model.getFullValueString(ctx.arena, node.full_name, item_type) catch "";
            }
        } else if (view_mode == .table_only) {
            // Table mode
            if (model.data_table.isEditMode()) {
                break :blk try std.fmt.allocPrint(ctx.arena, "Editing: {s}", .{model.data_table.table_edit_buffer.items});
            } else if (model.data_table.getCursorItemName()) |name| {
                if (model.data_table.getCursorItemType()) |item_type| {
                    break :blk model.getFullValueString(ctx.arena, name, item_type) catch "";
                }
            }
        }
        break :blk "";
    };

    // Build key hints for right side
    const key_hints = switch (view_mode) {
        .tree_only => "Ctrl+T=Table View | Space=Check +/-=Visibility /=Search Esc=Clear",
        .table_only => "Ctrl+T=Tree View | Space=Check /=Search Esc=Clear",
    };

    // Get max width
    const max_width = ctx.max.size().width;
    const height: u16 = 1;

    // Create surface
    var surface = try vxfw.Surface.init(
        ctx.arena,
        @constCast(model).widget(),
        .{ .width = max_width, .height = height },
    );

    // Initialize with default cells
    const base_cell: vaxis.Cell = .{ .default = true };
    @memset(surface.buffer, base_cell);

    // Style for status line
    const style = vaxis.Style{ .dim = true };

    // Write cursor value on left
    var col: u16 = 0;
    if (cursor_value_text.len > 0) {
        var iter = ctx.graphemeIterator(cursor_value_text);
        while (iter.next()) |char| {
            if (col >= max_width) break;
            const grapheme = char.bytes(cursor_value_text);
            const grapheme_width: u8 = @intCast(ctx.stringWidth(grapheme));
            surface.writeCell(col, 0, .{
                .char = .{ .grapheme = grapheme, .width = grapheme_width },
                .style = style,
            });
            col += grapheme_width;
        }
    }

    // Calculate position for right-aligned key hints
    const key_hints_width = ctx.stringWidth(key_hints);
    const key_hints_start = if (max_width > key_hints_width)
        @as(u16, @intCast(max_width - key_hints_width))
    else
        0;

    // Write key hints on right
    col = key_hints_start;
    var iter = ctx.graphemeIterator(key_hints);
    while (iter.next()) |char| {
        if (col >= max_width) break;
        const grapheme = char.bytes(key_hints);
        const grapheme_width: u8 = @intCast(ctx.stringWidth(grapheme));
        surface.writeCell(col, 0, .{
            .char = .{ .grapheme = grapheme, .width = grapheme_width },
            .style = style,
        });
        col += grapheme_width;
    }

    return surface;
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
