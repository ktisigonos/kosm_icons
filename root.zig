//! Icons: an icon theme in the kosmos' colors, or one installed on the system, by name.

const std = @import("std");

/// The icon theme; build one with `from`.
pub const App = @import("App.zig");
/// BeautyLine in the theme's colors.
pub const from = App.from;
/// BeautyLine's gradients and how its other colors change.
pub const BeautyLine = @import("BeautyLine.zig");
/// The colors a two-stop gradient becomes.
pub const Gradient = @import("Gradient.zig");
/// A theme installed on the system.
pub const System = @import("System.zig");
/// How an icon's colors change: by the palette, tinted or flat.
pub const Recolor = @import("recolor.zig").Recolor;
/// The palette `Recolor.palette` picks from.
pub const Nearest = @import("Nearest.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(App);
    std.testing.refAllDecls(BeautyLine);
    std.testing.refAllDecls(Nearest);
    std.testing.refAllDecls(@import("recolor.zig"));
    std.testing.refAllDecls(@import("svg.zig"));
}
