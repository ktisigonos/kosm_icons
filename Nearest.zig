//! The palette colors `Recolor.palette` picks from, and how it picks.

const Nearest = @This();

const std = @import("std");
const kosm = @import("kosm");

/// The colors to pick from. Default (`from`): the theme's palette.
palette: kosm.Palette.Resolved,
/// Below this OKLCH chroma (0..0.37) a color counts as gray. Default: 0.04.
gray_chroma: f64 = 0.04,

/// Picks from the theme's palette.
pub fn from(theme: kosm.Theme) Nearest {
    return .{ .palette = theme.palette };
}

/// The color `color` becomes.
pub fn apply(nearest: Nearest, color: kosm.Color) kosm.Color {
    if (color.chroma < nearest.gray_chroma) return nearest.gray(color);
    const target = nearest.palette.get(wheelPosition(color.hue));
    return .{ .lightness = color.lightness, .chroma = target.chroma, .hue = target.hue, .alpha = color.alpha };
}

/// The palette's black-to-white ramp at `color`'s lightness.
fn gray(nearest: Nearest, color: kosm.Color) kosm.Color {
    const black = nearest.palette.black;
    const white = nearest.palette.white;
    const span = white.lightness - black.lightness;
    const amount = if (@abs(span) < 1e-9) 0 else std.math.clamp((color.lightness - black.lightness) / span, 0, 1);
    var mixed = black.mix(white, amount);
    mixed.alpha = color.alpha;
    return mixed;
}

/// The wheel position whose pure sRGB color (`#ff0000` for red, `#ff8000` for orange, ...) is
/// nearest `hue` in OKLCH: icons are drawn in sRGB, so a color belongs to the hue it was
/// picked as, whatever the palette's own hues are.
pub fn wheelPosition(hue: f64) kosm.Palette.Hue {
    var best: kosm.Palette.Hue = .red;
    var best_distance: f64 = std.math.inf(f64);
    for (std.enums.values(kosm.Palette.Hue)) |position| {
        const difference = @abs(kosm.Color.wrapHue(hue - wheel_hues.get(position) + 180) - 180);
        if (difference < best_distance) {
            best = position;
            best_distance = difference;
        }
    }
    return best;
}

/// The OKLCH hue of each wheel position's pure sRGB color.
const wheel_hues: std.EnumArray(kosm.Palette.Hue, f64) = blk: {
    @setEvalBranchQuota(100_000);
    break :blk .init(.{
        .red = kosm.hex("ff0000").hue,
        .orange = kosm.hex("ff8000").hue,
        .yellow = kosm.hex("ffff00").hue,
        .lime = kosm.hex("80ff00").hue,
        .green = kosm.hex("00ff00").hue,
        .teal = kosm.hex("00ff80").hue,
        .cyan = kosm.hex("00ffff").hue,
        .sky = kosm.hex("0080ff").hue,
        .blue = kosm.hex("0000ff").hue,
        .purple = kosm.hex("8000ff").hue,
        .magenta = kosm.hex("ff00ff").hue,
        .pink = kosm.hex("ff0080").hue,
    });
};

const testing = std.testing;

fn testPalette() kosm.Palette.Resolved {
    return kosm.Palette.resolve(.{
        .black = kosm.hex("101010"),
        .white = kosm.hex("f0f0f0"),
        .red = kosm.hex("bf616a"),
        .blue = kosm.hex("5e81ac"),
        .cyan = kosm.hex("88c0d0"),
    });
}

test "a color goes to the palette color of its wheel position, keeping lightness and alpha" {
    const nearest: Nearest = .{ .palette = testPalette() };
    var source = kosm.hex("5570ff");
    source.alpha = 0.5;
    const result = nearest.apply(source);
    const blue = nearest.palette.blue;
    try testing.expectApproxEqAbs(source.lightness, result.lightness, 1e-9);
    try testing.expectApproxEqAbs(blue.chroma, result.chroma, 1e-9);
    try testing.expectApproxEqAbs(blue.hue, result.hue, 1e-9);
    try testing.expectEqual(0.5, result.alpha);
}

test "wheel positions follow the sRGB wheel, across the wrap at 0 deg" {
    try testing.expectEqual(.pink, wheelPosition(kosm.hex("fe0f7c").hue));
    try testing.expectEqual(.pink, wheelPosition(359));
    try testing.expectEqual(.red, wheelPosition(kosm.hex("fd2e00").hue));
    try testing.expectEqual(.cyan, wheelPosition(kosm.hex("4dd3ff").hue));
    try testing.expectEqual(.sky, wheelPosition(kosm.hex("0072ff").hue));
}

test "grays fall between the palette's black and white by lightness" {
    const nearest: Nearest = .{ .palette = testPalette() };
    try testing.expectApproxEqAbs(nearest.palette.white.lightness, nearest.apply(kosm.hex("ffffff")).lightness, 1e-9);
    try testing.expectApproxEqAbs(nearest.palette.black.lightness, nearest.apply(kosm.hex("000000")).lightness, 1e-9);
    const middle = nearest.apply(kosm.hex("777777"));
    try testing.expect(middle.lightness > nearest.palette.black.lightness and middle.lightness < nearest.palette.white.lightness);
}
