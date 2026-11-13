//! How an icon's colors change. Every mode keeps each color's alpha.

const std = @import("std");
const kosm = @import("kosm");
const Nearest = @import("Nearest.zig");

/// How an icon's colors change.
pub const Recolor = union(enum) {
    /// Each color moves to the palette color of its wheel position (nearest by hue), taking
    /// that color's hue and chroma and keeping its own lightness; grays fall between the
    /// palette's black and white by their lightness. Icons keep their shading in the
    /// palette's colors.
    palette: Nearest,
    /// Each color takes this color's hue and keeps its own lightness and chroma: the icons in
    /// one hue, still shaded. Grays stay gray.
    tint: kosm.Color,
    /// Each color becomes this color: the icons in one flat color.
    flat: kosm.Color,

    /// The color `color` becomes.
    pub fn apply(recolor: Recolor, color: kosm.Color) kosm.Color {
        return switch (recolor) {
            .palette => |nearest| nearest.apply(color),
            .tint => |tint| .{ .lightness = color.lightness, .chroma = color.chroma, .hue = tint.hue, .alpha = color.alpha },
            .flat => |flat| .{ .lightness = flat.lightness, .chroma = flat.chroma, .hue = flat.hue, .alpha = color.alpha },
        };
    }
};

const testing = std.testing;

test "a tint keeps lightness and chroma, a flat color keeps only alpha" {
    const source = kosm.hex("fd5900");
    const red = kosm.hex("ff0000");
    const tinted = (Recolor{ .tint = red }).apply(source);
    try testing.expectEqual(source.lightness, tinted.lightness);
    try testing.expectEqual(source.chroma, tinted.chroma);
    try testing.expectEqual(red.hue, tinted.hue);
    const gray = (Recolor{ .tint = red }).apply(kosm.hex("808080"));
    try testing.expect(gray.chroma < 1e-6);

    var translucent = source;
    translucent.alpha = 0.25;
    const flat = (Recolor{ .flat = red }).apply(translucent);
    try testing.expectEqual(red.lightness, flat.lightness);
    try testing.expectEqual(red.hue, flat.hue);
    try testing.expectEqual(0.25, flat.alpha);
}
