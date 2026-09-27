const std = @import("std");
const Io = std.Io;

const sub = @import("sub");

const Stats = struct {
    sum: i64,
    count: u32,
    min: i16,
    max: i16,
};

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
    var file_reader = file.reader(io, &buf);
    const reader = &file_reader.interface;

    // Initialize station hash map
    const StatsMap = std.StringHashMapUnmanaged(Stats);
    var map: StatsMap = .empty;
    try map.ensureTotalCapacity(gpa, 10_000);
    defer map.deinit(gpa);
    defer {
        var it = map.keyIterator();
        while (it.next()) |k| gpa.free(k.*);
    }

    // Iterate through each line and insert into map
    // const start = Io.Clock.awake.now(io);
    // var last = start;
    while (try reader.takeDelimiter('\n')) |line| {
        // Max temperature string lengh is 5
        // Min temperature string lengh is 3
        // Vientiane;-26.8
        //          ^
        // 0123456789
        const dim = findScalarLastPos(u8, line, line.len - 3, ';').?;
        const station = line[0..dim];
        const temp_str = line[(dim + 1)..];
        const temp = parseTemp(temp_str);

        const gop = map.getOrPutAssumeCapacity(station);
        if (gop.found_existing) {
            if (temp < gop.value_ptr.min) gop.value_ptr.min = temp;
            if (temp > gop.value_ptr.max) gop.value_ptr.max = temp;
            gop.value_ptr.sum += temp;
            gop.value_ptr.count += 1;
        } else {
            gop.key_ptr.* = try gpa.dupe(u8, station);
            gop.value_ptr.min = temp;
            gop.value_ptr.max = temp;
            gop.value_ptr.sum = temp;
            gop.value_ptr.count = 1;
        }
    }

    var keys = try gpa.alloc([]const u8, map.count());
    defer gpa.free(keys);

    var it = map.keyIterator();
    var i: usize = 0;
    while (it.next()) |k| : (i += 1) keys[i] = k.*;

    std.mem.sort([]const u8, keys, {}, lessThan);

    var stdout_buf: [4096]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &stdout_buf);
    const writer = &stdout.interface;

    try writer.writeByte('{');
    var first: bool = true;
    for (keys) |k| {
        const v = map.get(k).?;

        const avg = @as(f32, @floatFromInt(v.sum)) / @as(f32, @floatFromInt(v.count * 10));
        const min = backToFloat(v.min);
        const max = backToFloat(v.max);

        if (first) {
            try writer.print("{s}={d:.1}/{d:.1}/{d:.1}", .{ k, min, avg, max });
            first = false;
        } else {
            try writer.print(", {s}={d:.1}/{d:.1}/{d:.1}", .{ k, min, avg, max });
        }
    }
    try writer.writeByte('}');
    try writer.writeByte('\n');
    try writer.flush();
}
