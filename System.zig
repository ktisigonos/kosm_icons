//! An icon theme installed on the system, used by name or recolored.

const Recolor = @import("Recolor.zig");

/// The theme's folder name (`Papirus-Dark`), which programs pick it by.
name: []const u8,
/// Recolors the theme into the app's `directory` when set, which programs then pick instead.
/// null (default): the theme is used as is and nothing is written.
recolor: ?Recolor = null,
/// The folder the theme is installed in, `~/...` or absolute. null (default):
/// `/usr/share/icons/<name>`.
path: ?[]const u8 = null,
