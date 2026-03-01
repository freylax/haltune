//! TabBar widget for displaying tabs at top of TUI
//!
//! This module provides TabBar, a widget that displays tabs at the top
//! of the screen with keyboard shortcut hints. The active tab is highlighted
//! with reverse video.
//!
//! Features:
//! - Display tabs with names
//! - Show keyboard hints (e.g., "1", "2", "3" for Alt+Number shortcuts)
//! - Highlight active tab with reverse video
//! - Separator spaces between tabs

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");

/// Tab data structure
pub const Tab = struct {
    /// Tab name (display text)
    name: []const u8,

    /// Keyboard shortcut hint (e.g., "1", "2", "3")
    key_hint: ?[]const u8 = null,
};

/// TabBar widget for displaying tabs at top of TUI
pub const TabBar = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,

    /// List of tabs
    tabs: std.ArrayListUnmanaged(Tab),

    /// Index of currently selected tab
    selected_idx: usize = 0,

    /// Scroll offset (for when tabs don't fit on screen)
    scroll_offset: usize = 0,

    /// Initialize a new TabBar
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///
    /// Returns:
    ///   - Initialized TabBar with empty tab list
    pub fn init(allocator: std.mem.Allocator) TabBar {
        return .{
            .allocator = allocator,
            .tabs = .{},
        };
    }

    /// Clean up TabBar resources
    pub fn deinit(self: *TabBar) void {
        for (self.tabs.items) |t| {
            if (t.key_hint) |h| self.allocator.free(h);
            self.allocator.free(t.name);
        }
        self.tabs.deinit(self.allocator);
    }

    /// Add a tab to the TabBar
    ///
    /// Parameters:
    ///   - name: Tab name (display text)
    ///   - key_hint: Optional keyboard shortcut hint (e.g., "1", "2", "3")
    ///
    /// Returns:
    ///   - error.OutOfMemory if allocation fails
    pub fn addTab(self: *TabBar, name: []const u8, key_hint: ?[]const u8) !void {
        const hint = if (key_hint) |h| try self.allocator.dupe(u8, h) else null;
        errdefer if (hint) |h| self.allocator.free(h);
        try self.tabs.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .key_hint = hint,
        });
    }

    /// Get the currently selected tab
    ///
    /// Returns:
    ///   - Selected Tab, or null if no tabs or index out of range
    pub fn getSelected(self: *const TabBar) ?Tab {
        if (self.selected_idx >= self.tabs.items.len) return null;
        return self.tabs.items[self.selected_idx];
    }

    /// Set the selected tab by index
    ///
    /// Parameters:
    ///   - idx: Index of tab to select
    pub fn setSelected(self: *TabBar, idx: usize) void {
        if (idx < self.tabs.items.len) {
            self.selected_idx = idx;
        }
    }

    /// Return a vxfw.Widget for this TabBar
    pub fn widget(self: *TabBar) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = null, // No event handling - selection is managed externally
            .drawFn = struct {
                fn draw(ptr: *anyopaque, ctx: vxfw.DrawContext) !vxfw.Surface {
                    const tb: *TabBar = @ptrCast(@alignCast(ptr));
                    return tb.draw(ctx);
                }
            }.draw,
        };
    }

    /// Draw function - renders the tab bar
    pub fn draw(self: *TabBar, ctx: vxfw.DrawContext) !vxfw.Surface {
        const width = ctx.max.width orelse 80;
        const height: u16 = 1;

        // Create surface
        var surface = try vxfw.Surface.init(
            ctx.arena,
            self.widget(),
            .{ .width = width, .height = height },
        );

        // Initialize buffer with default cells
        const base_cell: vaxis.Cell = .{ .default = true };
        @memset(surface.buffer, base_cell);

        // Draw tabs
        var x: usize = 0;
        for (self.tabs.items, 0..) |tab, i| {
            const is_selected = (i == self.selected_idx);

            // Draw opening bracket for selected tab
            if (is_selected and x < width) {
                surface.writeCell(@intCast(x), 0, .{
                    .char = .{ .grapheme = "[", .width = 1 },
                    .style = .{ .reverse = true },
                });
                x += 1;
            } else if (x < width) {
                surface.writeCell(@intCast(x), 0, .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{},
                });
                x += 1;
            }

            // Draw tab name
            for (tab.name, 0..) |_, j| {
                if (x + j >= width) break;
                surface.writeCell(@intCast(x + j), 0, .{
                    .char = .{ .grapheme = tab.name[j..j+1], .width = 1 },
                    .style = if (is_selected) .{ .reverse = true } else .{},
                });
            }
            x += tab.name.len;

            // Draw key hint (if provided)
            if (tab.key_hint) |hint| {
                if (x < width) {
                    // Draw space before hint
                    surface.writeCell(@intCast(x), 0, .{
                        .char = .{ .grapheme = " ", .width = 1 },
                        .style = if (is_selected) .{ .reverse = true } else .{},
                    });
                    x += 1;
                }

                // Draw hint character
                if (x < width) {
                    surface.writeCell(@intCast(x), 0, .{
                        .char = .{ .grapheme = hint[0..1], .width = 1 },
                        .style = if (is_selected) .{ .reverse = true, .dim = true } else .{ .dim = true },
                    });
                    x += 1;
                }
            }

            // Draw closing bracket for selected tab or space separator
            if (is_selected and x < width) {
                surface.writeCell(@intCast(x), 0, .{
                    .char = .{ .grapheme = "]", .width = 1 },
                    .style = .{ .reverse = true },
                });
                x += 1;
            }

            // Separator space between tabs
            if (x < width) {
                surface.writeCell(@intCast(x), 0, .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{},
                });
                x += 1;
            }
        }

        return surface;
    }
};

// Compile-time tests to verify API surface
comptime {
    _ = TabBar.init;
    _ = TabBar.deinit;
    _ = TabBar.addTab;
    _ = TabBar.getSelected;
    _ = TabBar.setSelected;
    _ = TabBar.widget;
}
