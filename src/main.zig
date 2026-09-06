const std = @import("std");
const Io = std.Io;

// Keep at 128 bytes to fit in cache line.
const Stats = struct {
    sum: i64,
    count: u32,
    min: i16,
    max: i16,
};

const Table = struct {
    table: []Entry,

    const Entry = struct {
        key: []const u8,
        hash: u64,
        stats: Stats,

        fn isEmpty(self: Entry) bool {
            return self.key.len == 0;
        }
    };

    fn init(table: []Entry) Table {
        for (table) |*entry| {
            entry.key = &.{};
            entry.hash = 0;
            entry.stats = .{
                .sum = 0,
                .count = 0,
                .min = 1000,
                .max = -1000,
            };
        }
        return .{ .table = table };
    }

    fn get(self: Table, key: []const u8) *Entry {
        const hash = std.hash.Wyhash.hash(42, key);
        var i = hash % self.table.len;
        while (!self.table[i].isEmpty()) : (i = (i + 1) % self.table.len) {
            if (self.table[i].hash == hash) return &self.table[i];
        }
        self.table[i].hash = hash;
        return &self.table[i];
    }
};

fn pread(file: Io.File, buf: [*]u8, len: usize, pos: usize) !?usize {
    const n = std.posix.system.pread(file.handle, buf, len, @intCast(pos));
    if (n < 0) return error.ReadError;
    if (n == 0) return null;
    return @intCast(n);
}

fn backToFloat(i: i16) f32 {
    return @as(f32, @floatFromInt(i)) / 10;
}

fn charToDigit(ch: u8) i16 {
    return ch - '0';
}

fn parseTemp(temp: []const u8) i16 {
    var result: i16 = 0;
    var i = temp.len - 1;

    const ones = charToDigit(temp[i]);
    result = ones;

    i -= 2; // Skip '.'

    const tens = charToDigit(temp[i]);
    result += tens * 10;

    // Edge Cases:
    // 1. -10.0
    // 2. -0.0
    // 3. 10.0
    // 4. 0.0

    if (temp.len == 5) {
        result += charToDigit(temp[1]) * 100;
        result *= -1;
    } else if (temp.len == 4) {
        if (temp[0] == '-') {
            result *= -1;
        } else {
            result += charToDigit(temp[0]) * 100;
        }
    }

    return result;
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
    var buf: [4 * 1024 * 1024]u8 = undefined;
    const file = try Io.Dir.cwd().openFile(io, sub_path, .{});
    defer file.close(io);

    // Initialize station hash map
    var entries: [10_000]Table.Entry = undefined;
    const table = Table.init(&entries);
    var stations: std.ArrayList([]const u8) = .empty;
    try stations.ensureTotalCapacityPrecise(gpa, 10_000);
    defer {
        for (stations.items) |s| gpa.free(s);
        stations.deinit(gpa);
    }

    var off: usize = 0;
    while (try pread(file, &buf, buf.len, off)) |n| {
        var i: usize = 0;
        while (i < n) {
            const newline = std.mem.findScalarPos(u8, &buf, i, '\n') orelse break;
            // Max temperature string lengh is 5
            // Min temperature string lengh is 3
            // Vientiane;-26.8
            //          ^
            // 0123456789
            const semi = findScalarLastPos(u8, &buf, newline - 3, ';') orelse break;

            const start = i;
            i = newline + 1;

            const station = buf[start..semi];
            const temp = parseTemp(buf[semi + 1 .. newline]);

            const entry = table.get(station);
            entry.stats.sum += temp;
            entry.stats.count += 1;
            if (temp < entry.stats.min) entry.stats.min = temp;
            if (temp > entry.stats.max) entry.stats.max = temp;
            if (entry.isEmpty()) {
                entry.key = try gpa.dupe(u8, station);
                try stations.append(gpa, entry.key);
            }
        }
        off += i;
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
        const min = backToFloat(v.min);
        const max = backToFloat(v.max);

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
