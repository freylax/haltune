const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");
const Model = @import("model.zig").Model;
const ViewMode = @import("model.zig").ViewMode;
const TreeView = @import("widgets/tree_view.zig").TreeView;
const DataTable = @import("widgets/data_table.zig").DataTable;
const ItemType = @import("widgets/data_table.zig").ItemType;
const TreeNode = @import("widgets/tree_view.zig").Node;
const SignalDialog = @import("widgets/signal_dialog.zig").SignalDialog;
const TabBar = @import("widgets/tabbar.zig").TabBar;

/// Height of the tab bar in rows
const tab_bar_height: u16 = 1;

/// Draw function for conditional single-panel layout
/// Renders TabBar at top, then either tree view or table view based on current_view
pub fn drawTwoPanelLayout(
    ptr: *anyopaque,
    ctx: vxfw.DrawContext,
) std.mem.Allocator.Error!vxfw.Surface {
    const self: *Model = @ptrCast(@alignCast(ptr));

    // Get maximum available size
    const max = ctx.max.size();

    // Draw signal dialog if visible
    if (self.signal_dialog.visible) {
        // Signal dialog draws inline to the main surface
        // Just continue to normal rendering
    }

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

    // Reserve space for tab bar (top) and help text (bottom)
    const help_height: u16 = 1;
    const available_height = if (max.height > tab_bar_height + help_height)
        max.height - tab_bar_height - help_height
    else if (max.height > tab_bar_height)
        max.height - tab_bar_height
    else
        max.height;

    const panel_height = available_height;

    // Draw the TabBar at the top
    const tab_bar_widget = self.tab_bar.widget();
    const tab_bar_ctx = ctx.withConstraints(
        .{ .width = max.width, .height = tab_bar_height },
        .{ .width = max.width, .height = tab_bar_height },
    );
    const tab_bar_surface = try tab_bar_widget.drawFn(tab_bar_widget.userdata, tab_bar_ctx);

    // Render layout based on current view mode and active tab
    // If plugin tab is active (active_tab_idx > 0), show split view: tree (left) + plugin (right)
    if (self.active_tab_idx > 0) {
        std.log.info("Layout: plugin tab active (idx={d}), creating split view", .{self.active_tab_idx});
        // Calculate split widths: 40% tree, 60% plugin
        const tree_width = @as(u16, @intCast(@divFloor(max.width * 4, 10)));
        const plugin_width = max.width - tree_width;

        // Create left panel (tree view)
        const tree_surface = try createLeftPanel(self, ctx, tree_width, panel_height);

        // Create right panel (plugin widget)
        const plugin_manager_mod = @import("../plugin/manager.zig");
        const plugin_manager = plugin_manager_mod.getGlobalPluginManager();
        const plugin_names = self.config.enabled_plugins orelse &[_][]const u8{};
        const plugin_idx = self.active_tab_idx - 1;

        var plugin_surface: vxfw.Surface = undefined;
        var has_plugin = false;

        if (plugin_idx < plugin_names.len) {
            const plugin_name = plugin_names[plugin_idx];
            std.log.info("Layout: getting plugin widget for '{s}'", .{plugin_name});

            if (plugin_manager) |pm| {
                // Get plugin widget - activate plugin first if not already active
                var plugin_widget = pm.getPluginWidgetByName(plugin_name);
                if (plugin_widget == null) {
                    std.log.info("Layout: plugin '{s}' not active, activating now", .{plugin_name});
                    pm.activatePlugin(plugin_name) catch |err| {
                        std.log.err("Failed to activate plugin '{s}': {}", .{plugin_name, err});
                    };
                    // Try getting widget again after activation
                    plugin_widget = pm.getPluginWidgetByName(plugin_name);
                }

                if (plugin_widget) |widget| {
                    std.log.info("Layout: got plugin widget, drawing...", .{});
                    // Draw plugin widget with plugin width
                    const plugin_ctx = ctx.withConstraints(
                        .{ .width = plugin_width, .height = panel_height },
                        .{ .width = plugin_width, .height = panel_height },
                    );
                    plugin_surface = try widget.drawFn(widget.userdata, plugin_ctx);
                    has_plugin = true;
                }
            }
        }

        // Allocate children array (tab_bar + tree + plugin + help text)
        const child_count = if (has_plugin) @as(usize, 4) else @as(usize, 3);
        const children = try ctx.arena.alloc(vxfw.SubSurface, child_count);

        // Tab bar at top (row 0)
        children[0] = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = tab_bar_surface,
        };

        // Tree panel: left side
        children[1] = .{
            .origin = .{ .row = tab_bar_height, .col = 0 },
            .surface = tree_surface,
        };

        // Plugin panel: right side
        if (has_plugin) {
            children[2] = .{
                .origin = .{ .row = tab_bar_height, .col = tree_width },
                .surface = plugin_surface,
            };
        }

        // Help text at bottom
        const help_text = try createPluginHelpText(ctx, self);
        const help_idx = if (has_plugin) @as(usize, 3) else @as(usize, 2);
        children[help_idx] = .{
            .origin = .{ .row = tab_bar_height + panel_height, .col = 0 },
            .surface = help_text,
        };

        // Return the root surface with children
        std.log.info("Layout: returning split view with tree ({} wide) + plugin ({} wide)",
            .{tree_width, if (has_plugin) plugin_width else 0});
        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }

    // Render layout based on current view mode
    std.log.info("Layout: entering switch statement for current_view={}", .{self.current_view});
    return switch (self.current_view) {
        .tree_only => {
            std.log.info("Layout: creating TREE surface (active_tab_idx={d})", .{self.active_tab_idx});
            // Create full-width tree panel surface
            const tree_surface = try createLeftPanel(self, ctx, max.width, panel_height);

            // Allocate children array (tab_bar + tree + help text)
            const children = try ctx.arena.alloc(vxfw.SubSurface, 3);

            // Tab bar at top (row 0)
            children[0] = .{
                .origin = .{ .row = 0, .col = 0 },
                .surface = tab_bar_surface,
            };

            // Tree panel: positioned below tab bar (row 1)
            children[1] = .{
                .origin = .{ .row = tab_bar_height, .col = 0 },
                .surface = tree_surface,
            };

            // Help text at bottom
            const help_text = try createHelpText(ctx, .tree_only, self);
            children[2] = .{
                .origin = .{ .row = tab_bar_height + panel_height, .col = 0 },
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

            // Allocate children array (tab_bar + table + help text)
            const children = try ctx.arena.alloc(vxfw.SubSurface, 3);

            // Tab bar at top (row 0)
            children[0] = .{
                .origin = .{ .row = 0, .col = 0 },
                .surface = tab_bar_surface,
            };

            // Table panel: positioned below tab bar (row 1)
            children[1] = .{
                .origin = .{ .row = tab_bar_height, .col = 0 },
                .surface = table_surface,
            };

            // Help text at bottom
            const help_text = try createHelpText(ctx, .table_only, self);
            children[2] = .{
                .origin = .{ .row = tab_bar_height + panel_height, .col = 0 },
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
        .tree_only => try std.fmt.allocPrint(ctx.arena, "Tab:{d} Ctrl+T=Table | Space=Check +/-=Vis /=Search n=NewSignal s=Save Esc=Clear Ctrl+Q=Quit", .{model.active_tab_idx}),
        .table_only => try std.fmt.allocPrint(ctx.arena, "Tab:{d} Ctrl+T=Tree | Space=Check /=Search t=Type c=Comp Esc=Clear Ctrl+Q=Quit", .{model.active_tab_idx}),
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

/// Create help text for plugin view
fn createPluginHelpText(ctx: vxfw.DrawContext, model: *const Model) std.mem.Allocator.Error!vxfw.Surface {
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

    // Plugin help text - mention split view
    const key_hints = "Alt+1..N=Tab | Ctrl+T=View | Ctrl+Q=Quit | ↑↓=Nav Tree";

    // Calculate position for centered text
    const key_hints_width = ctx.stringWidth(key_hints);
    const key_hints_start = if (max_width > key_hints_width)
        @as(u16, @intCast((max_width - key_hints_width) / 2))
    else
        0;

    // Write key hints
    var col: u16 = key_hints_start;
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
