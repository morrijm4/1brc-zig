const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const root = @import("sub");
const Stats = root.Stats;
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

    if (args.len < 2) {
        return error.NoFilePath;
    }

    // Read file into a buffer
    const sub_path = args[1];
    const file = try Io.Dir.cwd().openFile(io, sub_path, .{});

    // Initialize station hash map
    var entries: [root.jobs][10_000]hash.Table.Entry = undefined;
    var tables: [root.jobs]hash.Table = undefined;
    for (&tables, &entries) |*table, *buffer| {
        table.* = hash.Table.init(buffer);
    }

    const intervals = try interval.create(root.jobs, gpa, io, file);
    defer gpa.free(intervals);

    var group: Io.Group = .init;
    for (intervals, tables) |int, table| {
        group.async(io, interval.process, .{
            gpa,
            file,
            table,
            int,
        });
    }
    try group.await(io);

    var stations: std.ArrayList([]const u8) = .empty;
    try stations.ensureTotalCapacityPrecise(gpa, 10_000);

    var agg_entries: [10_000]hash.Table.Entry = undefined;
    var aggregated = hash.Table.init(&agg_entries);
    interval.reduce(root.jobs, tables, &stations, aggregated);

    std.mem.sort([]const u8, stations.items, {}, lessThan);

    var stdout_buf: [4096]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &stdout_buf);
    const writer = &stdout.interface;

    try writer.writeByte('{');
    var first: bool = true;
    for (stations.items) |s| {
        const v = aggregated.get(s).stats;

        const fsum: f32 = @floatFromInt(v.sum);
        const fcount: f32 = @floatFromInt(v.count * 10);
        const avg = fsum / fcount;
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
