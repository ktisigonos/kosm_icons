const std = @import("std");

pub fn build(b: *std.Build) void {
    const module = @import("kosm").packageModule(b) orelse return;
    const beautyline = b.dependency("beautyline", .{});
    const options = b.addOptions();
    options.addOption([]const u8, "beautyline", beautylinePath(b, beautyline));
    module.addOptions("sources", options);
}

/// BeautyLine's absolute folder: the app reads it when a kosmos is applied, from wherever that runs.
fn beautylinePath(b: *std.Build, beautyline: *std.Build.Dependency) []const u8 {
    const path = beautyline.builder.root.joinString(b.allocator, ".") catch @panic("OOM");
    return std.Io.Dir.cwd().realPathFileAlloc(b.graph.io, path, b.allocator) catch |err|
        std.debug.panic("cannot find BeautyLine's folder {s}: {s}", .{ path, @errorName(err) });
}
