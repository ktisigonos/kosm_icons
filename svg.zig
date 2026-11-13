//! The colors in an SVG's text, and the same text with them replaced, every other byte kept.
//! Not an XML parser: it knows the spellings icons use (`#rgb`, `#rrggbb`, `#rrggbbaa`,
//! `rgb(...)`, `rgba(...)`, and `white` or `black` as a color property's value) and which colors
//! are a gradient's stops. Other named colors are kept as they are.

const std = @import("std");

/// An sRGB color, 8 bits a channel; alpha is never read or changed.
pub const Rgb = struct {
    red: u8,
    green: u8,
    blue: u8,

    /// Parses `rrggbb`, no `#`; comptime-known for tables.
    pub fn hex(comptime text: *const [6]u8) Rgb {
        return .{ .red = hexByte(text[0..2]), .green = hexByte(text[2..4]), .blue = hexByte(text[4..6]) };
    }

    fn hexByte(comptime text: *const [2]u8) u8 {
        return comptime (std.fmt.charToDigit(text[0], 16) catch @compileError("not a hex byte: " ++ text)) * 16 +
            (std.fmt.charToDigit(text[1], 16) catch @compileError("not a hex byte: " ++ text));
    }
};

/// One color in the text.
pub const Token = struct {
    /// The bytes replaced: the hex digits after `#` (not an alpha pair), the three channels
    /// inside `rgb(` or `rgba(`, or the name.
    start: usize,
    end: usize,
    rgb: Rgb,
    spelling: Spelling,
    /// The index in `Scan.gradients` of the gradient this color is a stop of, or null.
    gradient: ?usize,
};

/// How a token's color is written back.
pub const Spelling = enum {
    /// Six hex digits; `#rgb` becomes `#rrggbb`.
    hex,
    /// `r, g, b` in 0..255.
    channels,
    /// A name; written back as `#rrggbb`.
    name,
};

/// Every color of a text, in order, and its gradients' stops.
pub const Scan = struct {
    tokens: []const Token,
    /// Each gradient's stop colors, in order. A gradient with no stops of its own (one
    /// borrowing another's through `href`) is left out.
    gradients: []const []const Rgb,
};

/// Finds every color in `text`. The result lives in `allocator`.
pub fn scan(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error!Scan {
    var tokens: std.ArrayList(Token) = .empty;
    var gradients: std.ArrayList([]const Rgb) = .empty;
    var stops: std.ArrayList(Rgb) = .empty;
    var in_gradient = false;
    var index: usize = 0;
    while (index < text.len) {
        const rest = text[index..];
        if (rest[0] == '<') {
            if (startsWithAny(rest, &.{ "<linearGradient", "<radialGradient" })) {
                const tag_end = std.mem.indexOfScalarPos(u8, text, index, '>') orelse text.len;
                in_gradient = text[tag_end - 1] != '/';
                stops.clearRetainingCapacity();
            } else if (in_gradient and startsWithAny(rest, &.{ "</linearGradient", "</radialGradient" })) {
                in_gradient = false;
                if (stops.items.len != 0) try gradients.append(allocator, try allocator.dupe(Rgb, stops.items));
            }
            index += 1;
            continue;
        }
        const found = colorAt(text, index) orelse {
            index += 1;
            continue;
        };
        const gradient: ?usize = if (in_gradient) gradients.items.len else null;
        try tokens.append(allocator, .{ .start = found.start, .end = found.end, .rgb = found.rgb, .spelling = found.spelling, .gradient = gradient });
        if (in_gradient) try stops.append(allocator, found.rgb);
        index = @max(found.after, index + 1);
    }
    return .{ .tokens = tokens.items, .gradients = gradients.items };
}

/// `text` with each token's color replaced by `colors[i]`, the color for `scanned.tokens[i]`.
pub fn rewrite(allocator: std.mem.Allocator, text: []const u8, scanned: Scan, colors: []const Rgb) std.mem.Allocator.Error![]const u8 {
    std.debug.assert(colors.len == scanned.tokens.len);
    var written: std.Io.Writer.Allocating = try .initCapacity(allocator, text.len);
    const writer = &written.writer;
    var cursor: usize = 0;
    for (scanned.tokens, colors) |token, color| {
        writer.writeAll(text[cursor..token.start]) catch return error.OutOfMemory;
        const printed = switch (token.spelling) {
            .hex => writer.print("{x:0>2}{x:0>2}{x:0>2}", .{ color.red, color.green, color.blue }),
            .channels => writer.print("{d}, {d}, {d}", .{ color.red, color.green, color.blue }),
            .name => writer.print("#{x:0>2}{x:0>2}{x:0>2}", .{ color.red, color.green, color.blue }),
        };
        printed catch return error.OutOfMemory;
        cursor = token.end;
    }
    writer.writeAll(text[cursor..]) catch return error.OutOfMemory;
    return written.written();
}

const Found = struct {
    start: usize,
    end: usize,
    /// Where scanning goes on.
    after: usize,
    rgb: Rgb,
    spelling: Spelling,
};

fn colorAt(text: []const u8, index: usize) ?Found {
    const character = text[index];
    if (character == '#') return hexAt(text, index);
    if (index > 0 and isNameCharacter(text[index - 1])) return null;
    if (character == 'r') return functionAt(text, index);
    if (character == 'w' or character == 'b') return nameAt(text, index);
    return null;
}

/// `#` and 3, 6 or 8 hex digits, unless it is a reference (`url(#a)`, `href="#a"`) or an
/// entity (`&#123;`).
fn hexAt(text: []const u8, index: usize) ?Found {
    const before = text[0..index];
    if (std.mem.endsWith(u8, before, "url(") or std.mem.endsWith(u8, before, "&")) return null;
    if (std.mem.endsWith(u8, before, "href=\"") or std.mem.endsWith(u8, before, "href='")) return null;
    const start = index + 1;
    var end = start;
    while (end < text.len and std.ascii.isHex(text[end])) end += 1;
    if (end < text.len and isNameCharacter(text[end])) return null;
    const digits = text[start..end];
    const rgb: Rgb = switch (digits.len) {
        3 => .{ .red = doubled(digits[0]), .green = doubled(digits[1]), .blue = doubled(digits[2]) },
        6, 8 => .{ .red = byteAt(digits, 0), .green = byteAt(digits, 2), .blue = byteAt(digits, 4) },
        else => return null,
    };
    return .{ .start = start, .end = start + @min(digits.len, 6), .after = end, .rgb = rgb, .spelling = .hex };
}

/// `rgb(r, g, b)` or `rgba(r, g, b, a)`, channels as 0..255 numbers or percentages.
fn functionAt(text: []const u8, index: usize) ?Found {
    const rest = text[index..];
    const name_length: usize = if (std.mem.startsWith(u8, rest, "rgba(")) 5 else if (std.mem.startsWith(u8, rest, "rgb(")) 4 else return null;
    const start = index + name_length;
    const close = std.mem.indexOfScalarPos(u8, text, start, ')') orelse return null;
    var channels: [3]u8 = undefined;
    var parts = std.mem.tokenizeAny(u8, text[start..close], ", \t\n");
    var end = start;
    for (&channels) |*channel| {
        const part = parts.next() orelse return null;
        channel.* = parseChannel(part) orelse return null;
        end = @intFromPtr(part.ptr) - @intFromPtr(text.ptr) + part.len;
    }
    return .{ .start = start, .end = end, .after = close + 1, .rgb = .{ .red = channels[0], .green = channels[1], .blue = channels[2] }, .spelling = .channels };
}

fn parseChannel(text: []const u8) ?u8 {
    if (std.mem.endsWith(u8, text, "%")) {
        const percent = std.fmt.parseFloat(f64, text[0 .. text.len - 1]) catch return null;
        return @intFromFloat(@round(std.math.clamp(percent, 0, 100) * 2.55));
    }
    const value = std.fmt.parseFloat(f64, text) catch return null;
    return @intFromFloat(@round(std.math.clamp(value, 0, 255)));
}

const color_properties = [_][]const u8{ "fill", "stroke", "stop-color", "color", "flood-color", "lighting-color" };

/// `white` or `black` as the value of a color property: `fill="white"` or `fill:white`.
fn nameAt(text: []const u8, index: usize) ?Found {
    const rest = text[index..];
    const rgb: Rgb, const length: usize = if (std.mem.startsWith(u8, rest, "white"))
        .{ .{ .red = 255, .green = 255, .blue = 255 }, 5 }
    else if (std.mem.startsWith(u8, rest, "black"))
        .{ .{ .red = 0, .green = 0, .blue = 0 }, 5 }
    else
        return null;
    const end = index + length;
    if (end < text.len and isNameCharacter(text[end])) return null;
    if (!followsColorProperty(text[0..index])) return null;
    return .{ .start = index, .end = end, .after = end, .rgb = rgb, .spelling = .name };
}

/// Whether `before` ends with a color property and its `="`, `='` or `:`.
fn followsColorProperty(before: []const u8) bool {
    var end = before.len;
    while (end > 0 and std.ascii.isWhitespace(before[end - 1])) end -= 1;
    if (end == 0) return false;
    if (before[end - 1] == '"' or before[end - 1] == '\'') {
        end -= 1;
        if (end == 0 or before[end - 1] != '=') return false;
    } else if (before[end - 1] != ':') return false;
    end -= 1;
    while (end > 0 and std.ascii.isWhitespace(before[end - 1])) end -= 1;
    for (color_properties) |property| {
        if (!std.mem.endsWith(u8, before[0..end], property)) continue;
        const property_start = end - property.len;
        if (property_start == 0 or !isNameCharacter(before[property_start - 1])) return true;
    }
    return false;
}

fn isNameCharacter(character: u8) bool {
    return std.ascii.isAlphanumeric(character) or character == '_' or character == '-';
}

fn startsWithAny(text: []const u8, prefixes: []const []const u8) bool {
    for (prefixes) |prefix| {
        if (std.mem.startsWith(u8, text, prefix)) return true;
    }
    return false;
}

fn doubled(digit: u8) u8 {
    const value = std.fmt.charToDigit(digit, 16) catch unreachable; // checked by isHex
    return value * 17;
}

fn byteAt(digits: []const u8, offset: usize) u8 {
    return std.fmt.parseInt(u8, digits[offset .. offset + 2], 16) catch unreachable; // checked by isHex
}

const testing = std.testing;

fn expectRewrite(expected: []const u8, text: []const u8, color: Rgb) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const scanned = try scan(arena.allocator(), text);
    const colors = try arena.allocator().alloc(Rgb, scanned.tokens.len);
    @memset(colors, color);
    try testing.expectEqualStrings(expected, try rewrite(arena.allocator(), text, scanned, colors));
}

test "every spelling of a color is replaced, and only its color bytes" {
    const new: Rgb = .hex("102030");
    try expectRewrite(
        \\<path fill="#102030" stroke="#102030"/><stop style="stop-color:#10203080"/>
    ,
        \\<path fill="#FFF" stroke="#5570ff"/><stop style="stop-color:#5570ff80"/>
    , new);
    try expectRewrite(
        \\<stop style="stop-color:rgb(16, 32, 48);stop-opacity:1"/><g fill="rgba(16, 32, 48, 0.5)"/>
    ,
        \\<stop style="stop-color:rgb(85,112,255);stop-opacity:1"/><g fill="rgba(100%, 0%, 50%, 0.5)"/>
    , new);
    try expectRewrite(
        \\<path fill="#102030"/><g style="stroke: #102030"/><text>white black</text>
    ,
        \\<path fill="white"/><g style="stroke: black"/><text>white black</text>
    , new);
}

test "references, entities and ids that look like hex are left alone" {
    const text =
        \\<path fill="url(#abc)"/><use href="#bad"/><use xlink:href='#fed'/><t>&#123;</t><g id="a" class="#abcdefg"/>
    ;
    try expectRewrite(text, text, .hex("000000"));
}

test "a gradient's stops are grouped in order, and one borrowing stops has none" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const scanned = try scan(arena.allocator(),
        \\<path fill="#ffffff"/>
        \\<linearGradient id="a"><stop stop-color="#5570FF"/><stop offset="1" stop-color="#4DD3FF"/></linearGradient>
        \\<linearGradient id="b" href="#a"/>
        \\<radialGradient id="c"><stop style="stop-color:rgb(1,2,3)"/></radialGradient>
    );
    try testing.expectEqual(4, scanned.tokens.len);
    try testing.expectEqual(null, scanned.tokens[0].gradient);
    try testing.expectEqual(0, scanned.tokens[1].gradient.?);
    try testing.expectEqual(0, scanned.tokens[2].gradient.?);
    try testing.expectEqual(1, scanned.tokens[3].gradient.?);
    try testing.expectEqual(2, scanned.gradients.len);
    try testing.expectEqualSlices(Rgb, &.{ .hex("5570ff"), .hex("4dd3ff") }, scanned.gradients[0]);
    try testing.expectEqualSlices(Rgb, &.{.{ .red = 1, .green = 2, .blue = 3 }}, scanned.gradients[1]);
}
