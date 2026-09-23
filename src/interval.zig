const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const hash = @import("hash.zig");
const parse = @import("parse.zig");

pub const Interval = struct {
    start: u64,
    end: u64,
};

fn pread(file: Io.File, buf: [*]u8, len: usize, pos: usize) ?usize {
    const n = std.posix.system.pread(file.handle, buf, len, @intCast(pos));
    if (n < 0) @panic("Read failure");
    if (n == 0) return null;
    return @intCast(n);
}

/// Linear search for the last index of a scalar value inside a slice starting at `index`.
fn findScalarLastPos(comptime T: type, slice: []const T, index: usize, value: T) ?usize {
    var i: usize = index;
    while (i != 0) {
        i -= 1;
        if (slice[i] == value) return i;
    }
    return null;
}

pub fn process(
    gpa: Allocator,
    file: Io.File,
    table: hash.Table,
    int: Interval,
) Io.Cancelable!void {
    var buf: [4 * 1024 * 1024]u8 = undefined;
    var off: usize = int.start;

    while (pread(file, &buf, buf.len, off)) |n| {
        var i: usize = 0;
        while (i < n) {
            const newline = std.mem.findScalarPos(u8, &buf, i, '\n') orelse break;
            const semi = findScalarLastPos(u8, &buf, newline - 3, ';') orelse break;

            const start = i;
            i = newline + 1;

            if ((off + i) > int.end) {
                return;
            }

            const station = buf[start..semi];
            const temp = parse.temperature(buf[semi + 1 .. newline]);

            const entry = table.get(station);
            if (temp < entry.stats.min) entry.stats.min = temp;
            if (temp > entry.stats.max) entry.stats.max = temp;
            entry.stats.sum += temp;
            entry.stats.count += 1;
            if (entry.isEmpty()) {
                entry.key = gpa.dupe(u8, station) catch @panic("OOM");
            }
        }
        off += i;
    }
}

pub fn create(comptime n: u8, gpa: Allocator, io: Io, file: Io.File) ![]Interval {
    var buf: [128]u8 = undefined;
    var file_reader = file.reader(io, &buf);

    var intervals: std.ArrayList(Interval) = try .initCapacity(gpa, n);
    const stat = try file.stat(io);
    const block_size = @max(@divFloor(stat.size, n), 128);

    var i: u64 = 0;
    for (0..n) |_| {
        var int: Interval = undefined;

        try file_reader.seekBy(@as(i64, @intCast(block_size)));
        const chunk = file_reader.interface.takeDelimiterInclusive('\n') catch {
            int.start = i;
            int.end = stat.size;
            intervals.appendAssumeCapacity(int);
            break;
        };

        int.start = i;
        i += block_size + chunk.len;
        int.end = i;
        intervals.appendAssumeCapacity(int);
    }

    return intervals.items;
}

pub fn reduce(
    comptime n: u8,
    tables: [n]hash.Table,
    stations: *std.ArrayList([]const u8),
    aggregated: hash.Table,
) void {
    for (tables) |t| {
        for (t.table) |entry| {
            if (entry.isEmpty()) continue;

            var agg = aggregated.getHash(entry.hash);
            if (agg.isEmpty()) {
                agg.* = entry;
                stations.appendAssumeCapacity(entry.key);
            } else {
                agg.stats.count += entry.stats.count;
                agg.stats.sum += entry.stats.sum;

                if (entry.stats.min < agg.stats.min)
                    agg.stats.min = entry.stats.min;
                if (entry.stats.max > agg.stats.max)
                    agg.stats.max = entry.stats.max;
            }
        }
    }
}
