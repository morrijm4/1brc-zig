const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const root = @import("sub");
const hash = @import("hash.zig");
const interval = @import("interval.zig");

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
    io: Io,
    gpa: Allocator,
    file: Io.File,
    table: hash.Table,
    int: interval.Interval,
) Io.Cancelable!void {
    var buf: [4 * 1024 * 1024]u8 = undefined;
    var off: usize = int.start;

    while (pread(file, &buf, buf.len, off)) |n| {
        var i: usize = 0;
        while (i < n) {
            if ((off + i) > int.end) {
                return;
            }

            const newline = std.mem.findScalarPos(u8, &buf, i, '\n') orelse break;
            const semi = findScalarLastPos(u8, &buf, newline - 3, ';') orelse break;

            const start = i;
            i = newline + 1;

            const station = buf[start..semi];
            const temp = parse.temperature(buf[semi + 1 .. newline]);

            const entry = table.get(station);
            try entry.mutex.lock(io);
            if (temp < entry.stats.min) entry.stats.min = temp;
            if (temp > entry.stats.max) entry.stats.max = temp;
            entry.stats.sum += temp;
            entry.stats.count += 1;
            if (entry.isEmpty()) {
                entry.key = gpa.dupe(u8, station) catch @panic("OOM");
            }
            entry.mutex.unlock(io);
        }
        off += i;
    }
}

pub fn create(io: Io, file: Io.File) ![root.jobs]Interval {
    var buf: [128]u8 = undefined;
    var file_reader = file.reader(io, &buf);

    var intervals: [root.jobs]Interval = undefined;
    const stat = try file.stat(io);
    const block_size = @divFloor(stat.size, root.jobs);

    var i: u64 = 0;
    for (&intervals) |*int| {
        try file_reader.seekBy(@as(i64, @intCast(block_size)));
        const chunk = file_reader.interface.takeDelimiterInclusive('\n') catch {
            int.start = i;
            int.end = stat.size;
            continue;
        };

        int.start = i;
        i += block_size + chunk.len;
        int.end = i;
    }

    return intervals;
}
