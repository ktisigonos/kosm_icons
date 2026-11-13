//! An icon theme in the kosmos' colors, written whole to `directory`, or a theme installed on
//! the system picked by name. GTK, KDE and others pick it by `themeName`.

const App = @This();

const std = @import("std");
const kosm = @import("kosm");
const sources = @import("sources");
const svg = @import("svg.zig");
const Recolor = @import("recolor.zig").Recolor;
const BeautyLine = @import("BeautyLine.zig");
const System = @import("System.zig");

/// Which icons: an official set in the theme's colors, or a theme installed on the system.
/// null: nothing is written and no icon theme is picked. Default (`from`): BeautyLine.
icons: ?Icons = null,
/// The folder a generated theme is written to, `~/...` or absolute; its name is the name
/// programs pick the theme by. Files a former apply wrote there and this one doesn't are left.
/// Default: `~/.local/share/icons/kosm`.
directory: []const u8 = "~/.local/share/icons/kosm",
/// The name icon pickers show for a generated theme (`Name` in its index.theme). null
/// (default): the theme's `name`, or the name kosm applies the kosmos under.
name: ?[]const u8 = null,

/// The icons an app writes or picks.
pub const Icons = union(enum) {
    /// BeautyLine, recolored into `directory`.
    beautyline: BeautyLine,
    /// A theme installed on the system, used as is or recolored into `directory`.
    system: System,
};

/// BeautyLine in the theme's colors.
pub fn from(theme: kosm.Theme) App {
    return .{ .icons = .{ .beautyline = .from(theme) }, .name = theme.name };
}

/// The name programs pick the icon theme by: `directory`'s last folder for a generated theme,
/// the system theme's own name when it is used as is, null with no `icons`.
pub fn themeName(self: App) ?[]const u8 {
    const icons = self.icons orelse return null;
    if (icons == .system and icons.system.recolor == null) return icons.system.name;
    return std.Io.Dir.path.basename(self.directory);
}

/// Writes the generated theme, if any, as one group in diffs.
pub fn apply(self: App, output: *kosm.Output) !void {
    const icons = self.icons orelse return;
    switch (icons) {
        .beautyline => |set| try self.generate(output, sources.beautyline, .{ .beautyline = set }),
        .system => |system| {
            const recolor = system.recolor orelse return;
            const source = system.path orelse try std.Io.Dir.path.join(output.allocator, &.{ "/usr/share/icons", system.name });
            try self.generate(output, source, .{ .recolor = recolor });
        },
    }
}

/// Refreshes GTK's icon cache of a generated theme; a stale cache hides new icons from GTK.
pub fn reload(self: App, reloader: *kosm.Reloader) !void {
    const icons = self.icons orelse return;
    if (icons == .system and icons.system.recolor == null) return;
    try reloader.run(&.{ "gtk-update-icon-cache", "--force", "--quiet", self.directory });
}

/// What a generated theme's colors follow.
const Coloring = union(enum) {
    beautyline: BeautyLine,
    recolor: Recolor,
};

/// Copies the theme in `source` into `directory`: SVGs recolored (but symbolic ones),
/// index.theme renamed, links kept, every other file as is.
fn generate(self: App, output: *kosm.Output, source: []const u8, coloring: Coloring) !void {
    const allocator = output.allocator;
    var colors: Colors = .{ .allocator = allocator, .coloring = coloring };
    const display_name = try output.displayName(self.directory, self.name);
    for (try output.tree(source)) |entry| {
        // GTK's cache of the source folder; the reload writes one for this folder.
        if (std.mem.eql(u8, entry.path, "icon-theme.cache")) continue;
        const destination = try std.Io.Dir.path.join(allocator, &.{ self.directory, entry.path });
        if (entry.target) |target| {
            const kept = try keptTarget(output, source, entry.path, target);
            try output.link(.{ .file = destination, .target = kept, .group = self.directory });
            continue;
        }
        const content = try output.read(try std.Io.Dir.path.join(allocator, &.{ source, entry.path }));
        const written = if (std.mem.eql(u8, entry.path, "index.theme"))
            try renamedIndex(allocator, content, display_name)
        else if (isRecolored(entry.path))
            try colors.recolorSvg(content)
        else
            content;
        try output.verbatim(.{ .file = destination, .content = written, .group = self.directory });
    }
}

/// A link's target as it works from `directory`: a relative one pointing outside the theme
/// becomes the absolute path it pointed to.
fn keptTarget(output: *kosm.Output, source: []const u8, path: []const u8, target: []const u8) ![]const u8 {
    if (std.Io.Dir.path.isAbsolute(target)) return target;
    const allocator = output.allocator;
    const folder = std.Io.Dir.path.dirname(path) orelse "";
    const theme = try std.Io.Dir.path.resolvePosix(allocator, &.{source});
    const resolved = try std.Io.Dir.path.resolvePosix(allocator, &.{ source, folder, target });
    if (std.mem.startsWith(u8, resolved, theme) and resolved.len > theme.len and resolved[theme.len] == '/') return target;
    if (!std.Io.Dir.path.isAbsolute(resolved))
        return output.fail(path, "links outside the theme to {s}, which only works from an absolute theme path", .{target});
    return resolved;
}

/// Whether the file at `path` is an SVG to recolor: icons named or filed `symbolic` are colored
/// by toolkits and stay as they are.
fn isRecolored(path: []const u8) bool {
    if (!std.mem.endsWith(u8, path, ".svg")) return false;
    return std.mem.indexOf(u8, path, "symbolic") == null;
}

/// `content` with its first `Name=` line naming the theme `name`.
fn renamedIndex(allocator: std.mem.Allocator, content: []const u8, name: []const u8) ![]const u8 {
    var start: usize = 0;
    while (start < content.len) {
        const end = std.mem.indexOfScalarPos(u8, content, start, '\n') orelse content.len;
        if (std.mem.startsWith(u8, content[start..end], "Name="))
            return std.mem.concat(allocator, u8, &.{ content[0 .. start + "Name=".len], name, content[end..] });
        start = end + 1;
    }
    return content;
}

/// Recolors SVGs, converting each distinct color outside a mapped gradient once.
const Colors = struct {
    allocator: std.mem.Allocator,
    coloring: Coloring,
    cache: std.AutoHashMapUnmanaged(svg.Rgb, svg.Rgb) = .empty,

    fn recolorSvg(colors: *Colors, content: []const u8) ![]const u8 {
        const scanned = try svg.scan(colors.allocator, content);
        if (scanned.tokens.len == 0) return content;
        const replaced = try colors.allocator.alloc(svg.Rgb, scanned.tokens.len);
        var stop: usize = 0;
        for (scanned.tokens, replaced, 0..) |token, *color, index| {
            const same_gradient = index > 0 and token.gradient != null and std.meta.eql(scanned.tokens[index - 1].gradient, token.gradient);
            stop = if (same_gradient) stop + 1 else 0;
            const mapped = if (token.gradient) |gradient| colors.gradientStop(scanned.gradients[gradient], stop) else null;
            color.* = mapped orelse try colors.single(token.rgb);
        }
        return svg.rewrite(colors.allocator, content, scanned, replaced);
    }

    /// The color of stop `stop` of a gradient mapped as a whole, or null.
    fn gradientStop(colors: *const Colors, stops: []const svg.Rgb, stop: usize) ?svg.Rgb {
        const set = switch (colors.coloring) {
            .beautyline => |set| set,
            .recolor => return null,
        };
        if (set.all != null) return null;
        const gradient = set.gradient(stops) orelse return null;
        return toRgb(if (stop == 0) gradient.start else gradient.end);
    }

    fn single(colors: *Colors, rgb: svg.Rgb) !svg.Rgb {
        const entry = try colors.cache.getOrPut(colors.allocator, rgb);
        if (!entry.found_existing) entry.value_ptr.* = toRgb(colors.rule().apply(fromRgb(rgb)));
        return entry.value_ptr.*;
    }

    fn rule(colors: *const Colors) Recolor {
        return switch (colors.coloring) {
            .beautyline => |set| set.all orelse set.rest,
            .recolor => |recolor| recolor,
        };
    }
};

fn fromRgb(rgb: svg.Rgb) kosm.Color {
    return .fromRgb(.{ .red = channel(rgb.red), .green = channel(rgb.green), .blue = channel(rgb.blue), .alpha = 1 });
}

fn channel(value: u8) f64 {
    return @as(f64, @floatFromInt(value)) / 255;
}

/// `color` clipped to sRGB as kosm prints colors.
fn toRgb(color: kosm.Color) svg.Rgb {
    const text = color.hex();
    const digits = text.slice()[1..7];
    return .{ .red = hexByte(digits[0..2]), .green = hexByte(digits[2..4]), .blue = hexByte(digits[4..6]) };
}

fn hexByte(digits: []const u8) u8 {
    return std.fmt.parseInt(u8, digits, 16) catch unreachable; // Color.hex prints two hex digits a channel
}

const testing = std.testing;

const Fixture = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    plan: kosm.Plan,
    diagnostics: kosm.Diagnostics = .{},
    warnings: kosm.Warnings,
    home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined,
    output: kosm.Output,

    fn init(fixture: *Fixture) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io), .warnings = undefined, .output = undefined };
        fixture.warnings = .init(fixture.arena.allocator());
        const length = try fixture.tmp.dir.realPath(testing.io, &fixture.home_buffer);
        fixture.output = .{
            .allocator = fixture.arena.allocator(),
            .home = fixture.home_buffer[0..length],
            .adapters = &.{},
            .plan = &fixture.plan,
            .diagnostics = &fixture.diagnostics,
            .warnings = &fixture.warnings,
            .app = "icons",
            .kosmos = "frost",
        };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }

    fn write(fixture: *Fixture, path: []const u8, data: []const u8) !void {
        if (std.Io.Dir.path.dirname(path)) |folder| try fixture.tmp.dir.createDirPath(testing.io, folder);
        try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
    }

    fn planned(fixture: *Fixture, display_path: []const u8) []const u8 {
        const file = fixture.plan.find(fixture.absolute(display_path)) orelse return "(not planned)";
        return file.new;
    }

    fn linked(fixture: *Fixture, display_path: []const u8) []const u8 {
        const link = fixture.plan.findLink(fixture.absolute(display_path)) orelse return "(not planned)";
        return link.target;
    }

    fn absolute(fixture: *Fixture, display_path: []const u8) []const u8 {
        return std.Io.Dir.path.join(fixture.arena.allocator(), &.{ fixture.output.home, display_path[2..] }) catch @panic("OOM");
    }
};

const test_palette: kosm.Palette = .{ .black = kosm.hex("101010"), .white = kosm.hex("f0f0f0"), .blue = kosm.hex("5e81ac"), .red = kosm.hex("bf616a") };

test "a recolored system theme copies its files, recolors SVGs but symbolic ones, and keeps links" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try fixture.write("themes/Frost/index.theme", "[Icon Theme]\nName=Frost\nInherits=hicolor\n");
    try fixture.write("themes/Frost/icon-theme.cache", "stale");
    try fixture.write("themes/Frost/apps/firefox.svg", "<path fill=\"#ff0000\"/>");
    try fixture.write("themes/Frost/apps/go-symbolic.svg", "<path fill=\"#ff0000\"/>");
    try fixture.write("themes/Frost/COPYING", "GPL");
    try fixture.tmp.dir.symLink(testing.io, "firefox.svg", "themes/Frost/apps/browser.svg", .{});
    try fixture.tmp.dir.symLink(testing.io, "../../Other/x.svg", "themes/Frost/apps/other.svg", .{});

    const green = kosm.hex("00ff00");
    const theme_path = fixture.absolute("~/themes/Frost");
    const recolored: App = .{ .icons = .{ .system = .{ .name = "Frost", .path = theme_path, .recolor = .{ .flat = green } } }, .directory = "~/icons/kosm" };
    try recolored.apply(&fixture.output);

    try testing.expectEqualStrings("[Icon Theme]\nName=frost\nInherits=hicolor\n", fixture.planned("~/icons/kosm/index.theme"));
    try testing.expectEqualStrings("<path fill=\"#00ff00\"/>", fixture.planned("~/icons/kosm/apps/firefox.svg"));
    try testing.expectEqualStrings("<path fill=\"#ff0000\"/>", fixture.planned("~/icons/kosm/apps/go-symbolic.svg"));
    try testing.expectEqualStrings("GPL", fixture.planned("~/icons/kosm/COPYING"));
    try testing.expectEqualStrings("(not planned)", fixture.planned("~/icons/kosm/icon-theme.cache"));
    try testing.expectEqualStrings("firefox.svg", fixture.linked("~/icons/kosm/apps/browser.svg"));
    try testing.expectEqualStrings(fixture.absolute("~/themes/Other/x.svg"), fixture.linked("~/icons/kosm/apps/other.svg"));
    try testing.expectEqualStrings("~/icons/kosm", fixture.plan.files.items[0].group.?);
    try testing.expectEqualStrings("kosm", recolored.themeName().?);
}

test "a system theme used as is writes nothing and is picked by its own name" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const app: App = .{ .icons = .{ .system = .{ .name = "Papirus-Dark" } } };
    try app.apply(&fixture.output);
    try testing.expectEqual(0, fixture.plan.files.items.len);
    try testing.expectEqualStrings("Papirus-Dark", app.themeName().?);
    try testing.expectEqual(null, (App{}).themeName());
}

test "BeautyLine's known gradients take their fields' colors and the rest follows its rule" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const theme: kosm.Theme = .from(.{ .palette = test_palette, .mode = .dark });
    var set: BeautyLine = .from(theme);
    set.blue_cyan = .{ .start = kosm.hex("111111"), .end = kosm.hex("222222") };
    set.rest = .{ .flat = kosm.hex("333333") };
    var colors: Colors = .{ .allocator = fixture.arena.allocator(), .coloring = .{ .beautyline = set } };
    const icon =
        \\<path fill="url(#a)" stroke="#5570ff"/>
        \\<linearGradient id="a"><stop stop-color="#5570FF"/><stop offset="1" stop-color="#4DD3FF"/></linearGradient>
        \\<linearGradient id="b"><stop stop-color="#4DD3FF"/><stop offset="1" stop-color="#5570FF"/></linearGradient>
    ;
    try testing.expectEqualStrings(
        \\<path fill="url(#a)" stroke="#333333"/>
        \\<linearGradient id="a"><stop stop-color="#111111"/><stop offset="1" stop-color="#222222"/></linearGradient>
        \\<linearGradient id="b"><stop stop-color="#333333"/><stop offset="1" stop-color="#333333"/></linearGradient>
    , try colors.recolorSvg(icon));

    set.all = .{ .flat = kosm.hex("444444") };
    var all: Colors = .{ .allocator = fixture.arena.allocator(), .coloring = .{ .beautyline = set } };
    const recolored = try all.recolorSvg(icon);
    try testing.expectEqual(5, std.mem.count(u8, recolored, "#444444"));
}

test "the bundled BeautyLine is found and written as one group" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const app: App = .from(.from(.{ .palette = test_palette, .mode = .dark }));
    try app.apply(&fixture.output);
    try testing.expect(fixture.plan.files.items.len > 1000);
    try testing.expect(fixture.plan.links.items.len > 1000);
    try testing.expect(std.mem.indexOf(u8, fixture.planned("~/.local/share/icons/kosm/index.theme"), "\nName=frost\n") != null);
    const groups = try fixture.plan.changedGroups(testing.allocator);
    defer testing.allocator.free(groups);
    try testing.expectEqual(1, groups.len);
}
