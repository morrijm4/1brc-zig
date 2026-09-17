const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Stats = @import("sub").Stats;
const hash = @import("hash.zig");
const parse = @import("parse.zig");
const interval = @import("interval.zig");

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    defer arena.free(args);

    if (args.len < 2) {
        return error.NoFilePath;
    }

    // Read file into a buffer
    const sub_path = args[1];
    const file = try Io.Dir.cwd().openFile(io, sub_path, .{});
    defer file.close(io);

    // Initialize station hash map
    var entries: [10_000]hash.Table.Entry = undefined;
    const table = hash.Table.init(&entries);

    const intervals = try interval.create(io, file);

    var group: Io.Group = .init;
    for (intervals) |int| {
        group.async(io, interval.process, .{
            io,
            gpa,
            file,
            table,
            int,
        });
    }
    try group.await(io);

    var stations: std.ArrayList([]const u8) = .empty;
    try stations.ensureTotalCapacityPrecise(gpa, 10_000);
    defer {
        for (stations.items) |s| gpa.free(s);
        stations.deinit(gpa);
    }
    for (entries) |e| {
        if (!e.isEmpty()) {
            try stations.append(gpa, e.key);
        }
    }

    std.mem.sort([]const u8, stations.items, {}, lessThan);

    var stdout_buf: [4096]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &stdout_buf);
    const writer = &stdout.interface;

    try writer.writeByte('{');
    var first: bool = true;
    for (stations.items) |s| {
        const v = table.get(s).stats;

        const avg = @as(f32, @floatFromInt(v.sum)) / @as(f32, @floatFromInt(v.count * 10));
        const min = parse.toFloat(v.min);
        const max = parse.toFloat(v.max);

        if (first) {
            try writer.print("{s}={d:.1}/{d:.1}/{d:.1}", .{ s, min, avg, max });
            first = false;
        } else {
            try writer.print(", {s}={d:.1}/{d:.1}/{d:.1}", .{ s, min, avg, max });
        }
    }
    try writer.writeByte('}');
    try writer.writeByte('\n');
    try writer.flush();
}
