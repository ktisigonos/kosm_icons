//! How an icon's colors change: each color matches one of `colors` and `mode` says what it
//! becomes. Alpha never changes.

const Recolor = @This();

const std = @import("std");
const kosm = @import("kosm");

/// The theme whose palette hues and roles `colors` names, and between whose palette's black and
/// white grays fall.
theme: kosm.Theme,
/// The colors icons may take. Default: `.all`, the palette's twelve hues.
colors: Colors = .all,
/// What a color becomes from its match. Default: `.hue_and_chroma`.
mode: Mode = .hue_and_chroma,
/// What grays become. Default: `.ramp`.
grays: Grays = .ramp,
/// Below this OKLCH chroma (0..0.37) a color counts as gray. Default: 0.04.
gray_chroma: f64 = 0.04,

/// The colors icons may take.
pub const Colors = union(enum) {
    /// The palette's twelve hues.
    all,
    /// The palette's hues but these: `.{ .except = &.{ .yellow, .lime } }`.
    except: []const kosm.Palette.Hue,
    /// The theme's roles: `.{ .roles = &.{ .accent, .secondary } }`. Of two equally good
    /// matches, the first listed wins.
    roles: []const kosm.Theme.Roles.Name,
    /// These colors: `.{ .only = &.{ kosm.hex("2e8799"), kosm.hex("c0ff00") } }`. A list of
    /// colors known only when the kosmos runs is kept:
    /// `.{ .only = kosm.keep(kosm.Color, &.{ theme.palette.blue }) }`.
    /// Of two equally good matches, the first listed wins.
    only: []const kosm.Color,
};

/// What a color becomes. Every mode but `.nearest` matches by hue: a color goes to the
/// candidate whose wheel position (nearest pure sRGB hue: `#ff0000` red, `#ff8000` orange,
/// ...) is nearest its hue, since icons are drawn in sRGB colors picked by name.
pub const Mode = union(enum) {
    /// The match's hue and chroma, with its own lightness: icons keep their shading.
    hue_and_chroma,
    /// The match's hue, with its own lightness and chroma: pale stays pale.
    hue,
    /// The candidate nearest it as the eye sees (OKLab distance), exactly.
    nearest,
    /// Partway from itself to its match in OKLCH: 0 keeps it, 1 is the match.
    blend: f64,
    /// Whatever this function returns for the color and its match.
    custom: *const fn (color: kosm.Color, match: kosm.Color) kosm.Color,
};

/// What grays (chroma below `gray_chroma`) become.
pub const Grays = enum {
    /// Between the palette's black and white, by lightness: white outlines stay light.
    ramp,
    /// Left as they are.
    keep,
    /// Matched like any other color.
    match,
};

/// The theme's accent and secondary: each color becomes the one it looks nearest, grays fall
/// between the palette's black and white.
pub fn from(theme: kosm.Theme) Recolor {
    return .{ .theme = theme, .colors = .{ .roles = &.{ .accent, .secondary } }, .mode = .nearest };
}

/// Why this recolor cannot run, or null: there must be a color to pick and a blend in 0..1.
pub fn problem(recolor: *const Recolor) ?[]const u8 {
    if (recolor.candidateCount() == 0) return "recolor has no colors: `.only` or `.roles` is empty, or `.except` leaves out every hue";
    if (recolor.mode == .blend and !(recolor.mode.blend >= 0 and recolor.mode.blend <= 1)) return "recolor's `.blend` is outside 0..1";
    return null;
}

/// The color `color` becomes. Asserts `problem` is null.
pub fn apply(recolor: *const Recolor, color: kosm.Color) kosm.Color {
    if (color.chroma < recolor.gray_chroma) switch (recolor.grays) {
        .ramp => return recolor.ramp(color),
        .keep => return color,
        .match => {},
    };
    const match = if (recolor.mode == .nearest) recolor.nearestByEye(color) else recolor.nearestByHue(color);
    var result: kosm.Color = switch (recolor.mode) {
        .hue_and_chroma => .{ .lightness = color.lightness, .chroma = match.chroma, .hue = match.hue },
        .hue => .{ .lightness = color.lightness, .chroma = color.chroma, .hue = match.hue },
        .nearest => match,
        .blend => |amount| color.mix(match, amount),
        .custom => |function| function(color, match),
    };
    result.alpha = color.alpha;
    return result;
}

/// A color to match and the wheel position it counts as.
const Candidate = struct {
    color: kosm.Color,
    position: kosm.Palette.Hue,
};

fn candidateCount(recolor: *const Recolor) usize {
    var count: usize = 0;
    var iterator = recolor.candidates();
    while (iterator.next()) |_| count += 1;
    return count;
}

fn candidates(recolor: *const Recolor) Iterator {
    return .{ .recolor = recolor };
}

const Iterator = struct {
    recolor: *const Recolor,
    index: usize = 0,

    fn next(iterator: *Iterator) ?Candidate {
        const theme = &iterator.recolor.theme;
        switch (iterator.recolor.colors) {
            .roles => |names| {
                if (iterator.index >= names.len) return null;
                defer iterator.index += 1;
                const color = theme.roles.get(names[iterator.index]);
                return .{ .color = color, .position = wheelPosition(color.hue) };
            },
            .only => |colors| {
                if (iterator.index >= colors.len) return null;
                defer iterator.index += 1;
                const color = colors[iterator.index];
                return .{ .color = color, .position = wheelPosition(color.hue) };
            },
            .all, .except => {
                const positions = std.enums.values(kosm.Palette.Hue);
                while (iterator.index < positions.len) {
                    const position = positions[iterator.index];
                    iterator.index += 1;
                    if (iterator.recolor.colors == .except and std.mem.indexOfScalar(kosm.Palette.Hue, iterator.recolor.colors.except, position) != null) continue;
                    return .{ .color = theme.palette.get(position), .position = position };
                }
                return null;
            },
        }
    }
};

fn nearestByHue(recolor: *const Recolor, color: kosm.Color) kosm.Color {
    var best: kosm.Color = undefined;
    var best_distance: f64 = std.math.inf(f64);
    var iterator = recolor.candidates();
    while (iterator.next()) |candidate| {
        const distance = hueDistance(color.hue, wheel_hues.get(candidate.position));
        if (distance < best_distance) {
            best = candidate.color;
            best_distance = distance;
        }
    }
    return best;
}

fn nearestByEye(recolor: *const Recolor, color: kosm.Color) kosm.Color {
    var best: kosm.Color = undefined;
    var best_distance: f64 = std.math.inf(f64);
    var iterator = recolor.candidates();
    while (iterator.next()) |candidate| {
        const distance = labDistance(color, candidate.color);
        if (distance < best_distance) {
            best = candidate.color;
            best_distance = distance;
        }
    }
    return best;
}

/// The palette's black-to-white ramp at `color`'s lightness.
fn ramp(recolor: *const Recolor, color: kosm.Color) kosm.Color {
    const black = recolor.theme.palette.black;
    const white = recolor.theme.palette.white;
    const span = white.lightness - black.lightness;
    const amount = if (@abs(span) < 1e-9) 0 else std.math.clamp((color.lightness - black.lightness) / span, 0, 1);
    var mixed = black.mix(white, amount);
    mixed.alpha = color.alpha;
    return mixed;
}

fn hueDistance(first: f64, second: f64) f64 {
    return @abs(kosm.Color.wrapHue(first - second + 180) - 180);
}

/// Squared OKLab distance; ordering is all that matters.
fn labDistance(first: kosm.Color, second: kosm.Color) f64 {
    const lightness = first.lightness - second.lightness;
    const a = first.chroma * @cos(std.math.degreesToRadians(first.hue)) - second.chroma * @cos(std.math.degreesToRadians(second.hue));
    const b = first.chroma * @sin(std.math.degreesToRadians(first.hue)) - second.chroma * @sin(std.math.degreesToRadians(second.hue));
    return lightness * lightness + a * a + b * b;
}

/// The wheel position whose pure sRGB color is nearest `hue` in OKLCH.
pub fn wheelPosition(hue: f64) kosm.Palette.Hue {
    var best: kosm.Palette.Hue = .red;
    var best_distance: f64 = std.math.inf(f64);
    for (std.enums.values(kosm.Palette.Hue)) |position| {
        const distance = hueDistance(hue, wheel_hues.get(position));
        if (distance < best_distance) {
            best = position;
            best_distance = distance;
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

fn testTheme() kosm.Theme {
    return .from(.{ .palette = .{
        .black = kosm.hex("101010"),
        .white = kosm.hex("f0f0f0"),
        .red = kosm.hex("bf616a"),
        .blue = kosm.hex("5e81ac"),
        .cyan = kosm.hex("88c0d0"),
    }, .mode = .dark });
}

fn expectColor(expected: kosm.Color, actual: kosm.Color) !void {
    try testing.expectApproxEqAbs(expected.lightness, actual.lightness, 1e-9);
    try testing.expectApproxEqAbs(expected.chroma, actual.chroma, 1e-9);
    try testing.expectApproxEqAbs(expected.hue, actual.hue, 1e-9);
    try testing.expectApproxEqAbs(expected.alpha, actual.alpha, 1e-9);
}

test "a color takes the hue and chroma of its wheel position's palette color, keeping lightness and alpha" {
    const recolor: Recolor = .{ .theme = testTheme() };
    var source = kosm.hex("5570ff");
    source.alpha = 0.5;
    const blue = recolor.theme.palette.blue;
    try expectColor(.{ .lightness = source.lightness, .chroma = blue.chroma, .hue = blue.hue, .alpha = 0.5 }, recolor.apply(source));
}

test "wheel positions follow the sRGB wheel, across the wrap at 0 deg" {
    try testing.expectEqual(.pink, wheelPosition(kosm.hex("fe0f7c").hue));
    try testing.expectEqual(.pink, wheelPosition(359));
    try testing.expectEqual(.red, wheelPosition(kosm.hex("fd2e00").hue));
    try testing.expectEqual(.cyan, wheelPosition(kosm.hex("4dd3ff").hue));
    try testing.expectEqual(.sky, wheelPosition(kosm.hex("0072ff").hue));
}

test "an excepted hue goes to the nearest hue left, across the wrap" {
    const theme = testTheme();
    const palette = theme.palette;
    const recolor: Recolor = .{ .theme = theme, .colors = .{ .except = &.{ .red, .pink, .orange } } };
    // Red's neighbours left are magenta (two positions back) and yellow (two on); pure red is
    // nearer magenta's pure hue in OKLCH.
    const result = recolor.apply(kosm.hex("ff0000"));
    try testing.expectApproxEqAbs(palette.magenta.hue, result.hue, 1e-9);
}

test "only listed colors are taken, raw or from the palette, by their own hue's position" {
    const theme = testTheme();
    const palette = theme.palette;
    const lime = kosm.hex("c0ff00");
    const recolor: Recolor = .{ .theme = theme, .colors = .{ .only = &.{ palette.blue, lime } } };
    try testing.expectApproxEqAbs(lime.hue, recolor.apply(kosm.hex("ffff00")).hue, 1e-9);
    try testing.expectApproxEqAbs(palette.blue.hue, recolor.apply(kosm.hex("8000ff")).hue, 1e-9);
    const first_wins: Recolor = .{ .theme = theme, .colors = .{ .only = &.{ lime, lime, palette.blue } } };
    try testing.expectApproxEqAbs(lime.hue, first_wins.apply(kosm.hex("80ff00")).hue, 1e-9);
}

test "each mode makes what it says of the color and its match" {
    const theme = testTheme();
    const source = kosm.hex("fd5900");
    const red = kosm.hex("ff0000");
    const only_red: Colors = .{ .only = &.{red} };

    const hue = (Recolor{ .theme = theme, .colors = only_red, .mode = .hue }).apply(source);
    try expectColor(.{ .lightness = source.lightness, .chroma = source.chroma, .hue = red.hue }, hue);

    var translucent = source;
    translucent.alpha = 0.25;
    var expected_red = red;
    expected_red.alpha = 0.25;
    try expectColor(expected_red, (Recolor{ .theme = theme, .colors = only_red, .mode = .nearest }).apply(translucent));

    const blend = (Recolor{ .theme = theme, .colors = only_red, .mode = .{ .blend = 0.5 } }).apply(source);
    try expectColor(source.mix(red, 0.5), blend);

    const custom = (Recolor{ .theme = theme, .colors = only_red, .mode = .{ .custom = &darkest } }).apply(translucent);
    try testing.expectApproxEqAbs(@min(source.lightness, red.lightness), custom.lightness, 1e-9);
    try testing.expectEqual(0.25, custom.alpha);
}

fn darkest(color: kosm.Color, match: kosm.Color) kosm.Color {
    return if (color.lightness < match.lightness) color else match;
}

test "nearest matches by lightness too, not only hue" {
    const theme = testTheme();
    const dark_blue = kosm.hex("000080");
    const recolor: Recolor = .{ .theme = theme, .colors = .{ .only = &.{ kosm.hex("ff8080"), dark_blue } }, .mode = .nearest };
    // A dark red is nearer the dark blue as the eye sees it than the light red.
    try expectColor(dark_blue, recolor.apply(kosm.hex("400000")));
}

test "grays ramp between black and white, stay, or match like colors" {
    const theme = testTheme();
    const palette = theme.palette;
    const ramped: Recolor = .{ .theme = theme };
    try testing.expectApproxEqAbs(palette.white.lightness, ramped.apply(kosm.hex("ffffff")).lightness, 1e-9);
    try testing.expectApproxEqAbs(palette.black.lightness, ramped.apply(kosm.hex("000000")).lightness, 1e-9);
    const middle = ramped.apply(kosm.hex("777777"));
    try testing.expect(middle.lightness > palette.black.lightness and middle.lightness < palette.white.lightness);

    const gray = kosm.hex("808080");
    try expectColor(gray, (Recolor{ .theme = theme, .grays = .keep }).apply(gray));
    const red = kosm.hex("ff0000");
    const flat: Recolor = .{ .theme = theme, .colors = .{ .only = &.{red} }, .mode = .nearest, .grays = .match };
    try expectColor(red, flat.apply(gray));
}

test "by default every color becomes the accent or secondary it looks nearest, grays a ramp" {
    const theme = testTheme();
    const recolor: Recolor = .from(theme);
    try expectColor(theme.roles.accent, recolor.apply(kosm.hex("4dd3ff")));
    try expectColor(theme.roles.secondary, recolor.apply(kosm.hex("0000ff")));
    const red = recolor.apply(kosm.hex("ff0000"));
    try testing.expect(std.meta.eql(red, theme.roles.accent) or std.meta.eql(red, theme.roles.secondary));
    try expectColor(theme.palette.black, recolor.apply(kosm.hex("000000")));
}

test "listed roles are taken by their own hue's position, the first winning a tie" {
    var theme = testTheme();
    theme.roles.success = kosm.hex("c0ff00");
    const recolor: Recolor = .{ .theme = theme, .colors = .{ .roles = &.{ .secondary, .success } } };
    try testing.expectApproxEqAbs(theme.roles.success.hue, recolor.apply(kosm.hex("ffff00")).hue, 1e-9);
    try testing.expectApproxEqAbs(theme.roles.secondary.hue, recolor.apply(kosm.hex("8000ff")).hue, 1e-9);
    theme.roles.link = theme.roles.success;
    theme.roles.link.chroma /= 2;
    const first_wins: Recolor = .{ .theme = theme, .colors = .{ .roles = &.{ .link, .success } }, .mode = .hue_and_chroma };
    try testing.expectApproxEqAbs(theme.roles.link.chroma, first_wins.apply(kosm.hex("80ff00")).chroma, 1e-9);
}

test "no colors to pick or a blend outside 0..1 is a problem" {
    const theme = testTheme();
    try testing.expectEqual(null, (Recolor{ .theme = theme }).problem());
    try testing.expect((Recolor{ .theme = theme, .colors = .{ .only = &.{} } }).problem() != null);
    try testing.expect((Recolor{ .theme = theme, .colors = .{ .roles = &.{} } }).problem() != null);
    try testing.expect((Recolor{ .theme = theme, .colors = .{ .except = std.enums.values(kosm.Palette.Hue) } }).problem() != null);
    try testing.expect((Recolor{ .theme = theme, .mode = .{ .blend = 1.5 } }).problem() != null);
}
