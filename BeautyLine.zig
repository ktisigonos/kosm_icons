//! BeautyLine (Garuda Linux, GPL-3.0): outline icons drawn in two-color gradients. Its most used
//! gradients become exact theme colors, named after the hues they go between; every other
//! color follows `rest`. Icons named `symbolic` are left alone: toolkits color them.

const BeautyLine = @This();

const std = @import("std");
const kosm = @import("kosm");
const Gradient = @import("Gradient.zig");
const Recolor = @import("recolor.zig").Recolor;
const svg = @import("svg.zig");

/// BeautyLine's `#5570ff` -> `#4dd3ff`. Default: the palette's blue -> cyan.
blue_cyan: Gradient,
/// BeautyLine's `#0357d1` -> `#27cdfc`, its folders. Default: sky -> cyan.
deep_blue_cyan: Gradient,
/// BeautyLine's `#5558ff` -> `#00c0ff`. Default: blue -> sky.
blue_sky: Gradient,
/// BeautyLine's `#0072ff` -> `#00e5a1`. Default: sky -> teal.
sky_teal: Gradient,
/// BeautyLine's `#00b59c` -> `#9cffac`. Default: cyan -> teal.
cyan_teal: Gradient,
/// BeautyLine's `#02aa93` -> `#67ff80`. Default: teal -> green.
teal_green: Gradient,
/// BeautyLine's `#a93aff` -> `#ff81ff`. Default: purple -> magenta.
purple_magenta: Gradient,
/// BeautyLine's `#8d01a2` -> `#ff00d2` and `#8d01a2` -> `#ff33db`. Default: purple -> pink.
plum_magenta: Gradient,
/// BeautyLine's `#fd5900` -> `#ffde00` and `#fda700` -> `#ffde00`. Default: orange -> yellow.
orange_yellow: Gradient,
/// BeautyLine's `#fe0844` -> `#feb302` and `#fd2e00` -> `#ff9900`. Default: red -> orange.
red_orange: Gradient,
/// BeautyLine's `#fe0f7c` -> `#df0066`. Default: pink -> magenta.
pink_magenta: Gradient,
/// BeautyLine's `#fd3a84` -> `#ffa68d`. Default: pink -> orange.
pink_peach: Gradient,
/// BeautyLine's `#fe7970` -> `#dc3282`. Default: red -> pink.
coral_pink: Gradient,
/// Every color the gradients above don't cover. Default: `.palette`, the theme's palette.
rest: Recolor,
/// Recolors every color this way instead, gradients included, when set. Default: null.
all: ?Recolor = null,

/// The gradients in the theme's palette, the rest by wheel position.
pub fn from(theme: kosm.Theme) BeautyLine {
    const palette = theme.palette;
    return .{
        .blue_cyan = .{ .start = palette.blue, .end = palette.cyan },
        .deep_blue_cyan = .{ .start = palette.sky, .end = palette.cyan },
        .blue_sky = .{ .start = palette.blue, .end = palette.sky },
        .sky_teal = .{ .start = palette.sky, .end = palette.teal },
        .cyan_teal = .{ .start = palette.cyan, .end = palette.teal },
        .teal_green = .{ .start = palette.teal, .end = palette.green },
        .purple_magenta = .{ .start = palette.purple, .end = palette.magenta },
        .plum_magenta = .{ .start = palette.purple, .end = palette.pink },
        .orange_yellow = .{ .start = palette.orange, .end = palette.yellow },
        .red_orange = .{ .start = palette.red, .end = palette.orange },
        .pink_magenta = .{ .start = palette.pink, .end = palette.magenta },
        .pink_peach = .{ .start = palette.pink, .end = palette.orange },
        .coral_pink = .{ .start = palette.red, .end = palette.pink },
        .rest = .{ .palette = .from(theme) },
    };
}

/// The field a gradient of BeautyLine's with `stops` maps to, or null.
pub fn gradient(set: BeautyLine, stops: []const svg.Rgb) ?Gradient {
    if (stops.len != 2) return null;
    inline for (sources) |source| {
        if (std.meta.eql(source.stops[0], stops[0]) and std.meta.eql(source.stops[1], stops[1]))
            return @field(set, source.field);
    }
    return null;
}

const Source = struct {
    stops: [2]svg.Rgb,
    field: []const u8,
};

const sources = [_]Source{
    .{ .stops = .{ .hex("5570ff"), .hex("4dd3ff") }, .field = "blue_cyan" },
    .{ .stops = .{ .hex("0357d1"), .hex("27cdfc") }, .field = "deep_blue_cyan" },
    .{ .stops = .{ .hex("5558ff"), .hex("00c0ff") }, .field = "blue_sky" },
    .{ .stops = .{ .hex("0072ff"), .hex("00e5a1") }, .field = "sky_teal" },
    .{ .stops = .{ .hex("00b59c"), .hex("9cffac") }, .field = "cyan_teal" },
    .{ .stops = .{ .hex("02aa93"), .hex("67ff80") }, .field = "teal_green" },
    .{ .stops = .{ .hex("a93aff"), .hex("ff81ff") }, .field = "purple_magenta" },
    .{ .stops = .{ .hex("8d01a2"), .hex("ff00d2") }, .field = "plum_magenta" },
    .{ .stops = .{ .hex("8d01a2"), .hex("ff33db") }, .field = "plum_magenta" },
    .{ .stops = .{ .hex("fd5900"), .hex("ffde00") }, .field = "orange_yellow" },
    .{ .stops = .{ .hex("fda700"), .hex("ffde00") }, .field = "orange_yellow" },
    .{ .stops = .{ .hex("fe0844"), .hex("feb302") }, .field = "red_orange" },
    .{ .stops = .{ .hex("fd2e00"), .hex("ff9900") }, .field = "red_orange" },
    .{ .stops = .{ .hex("fe0f7c"), .hex("df0066") }, .field = "pink_magenta" },
    .{ .stops = .{ .hex("fd3a84"), .hex("ffa68d") }, .field = "pink_peach" },
    .{ .stops = .{ .hex("fe7970"), .hex("dc3282") }, .field = "coral_pink" },
};

comptime {
    // Every gradient field has a source, so none is silently unused.
    for (@typeInfo(BeautyLine).@"struct".field_names, @typeInfo(BeautyLine).@"struct".field_types) |name, Type| {
        if (Type != Gradient) continue;
        for (sources) |source| {
            if (std.mem.eql(u8, source.field, name)) break;
        } else @compileError("BeautyLine." ++ name ++ " has no source gradient");
    }
}

const testing = std.testing;

test "a source gradient maps to its field, in stop order only" {
    const theme: kosm.Theme = .from(.{ .palette = .{ .black = kosm.hex("000000"), .white = kosm.hex("ffffff") }, .mode = .dark });
    var set: BeautyLine = .from(theme);
    set.orange_yellow = .{ .start = kosm.hex("ff8000"), .end = kosm.hex("ffff00") };
    try testing.expectEqual(set.orange_yellow, set.gradient(&.{ .hex("fda700"), .hex("ffde00") }).?);
    try testing.expectEqual(null, set.gradient(&.{ .hex("ffde00"), .hex("fda700") }));
    try testing.expectEqual(null, set.gradient(&.{.hex("fda700")}));
}
