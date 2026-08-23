const std = @import("std");
const mem = std.mem;
const process = std.process;
const Io = std.Io;
const Allocator = mem.Allocator;
const log = std.log;

const ExecError = process.RunError || Io.Writer.Error;

fn exec(gpa: Allocator, io: Io, cmd: []const u8, writer: *Io.Writer) ExecError!void {
    const result = try process.run(gpa, io, .{
        .argv = &.{ "time", "-l", cmd, "../measurements.txt" },
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    log.info("{s}", .{cmd});
    std.debug.print("{s}", .{result.stderr});

    var it = std.mem.tokenizeAny(u8, result.stderr, &std.ascii.whitespace);
    const wall_clock = it.next().?;
    try writer.print("{s},", .{wall_clock});
}

fn is_executable(mode: std.posix.mode_t) bool {
    return ((mode & 0x0FFF) & 0o111) > 0;
}

const BenchError = ExecError || Io.Writer.Error || Io.File.StatError || Io.File.SeekError;

fn bench(gpa: Allocator, io: Io, comptime dir: []const u8) BenchError!void {
    var buf: [64]u8 = undefined;
    const file = try Io.Dir.cwd().createFile(io, "./results.csv", .{ .truncate = false });
    defer file.close(io);

    // Append to file
    const stat = try file.stat(io);
    var file_writer = file.writer(io, &buf);
    try file_writer.seekTo(stat.size);
    const writer = &file_writer.interface;

    const modes = [_][]const u8{
        // "Debug",
        // "ReleaseSafe",
        // "ReleaseSmall",
        "ReleaseFast",
    };
    inline for (modes) |mode| {
        const cmd = dir ++ "/sub-" ++ mode;
        std.log.info("Executing {s}", .{mode});
        try exec(gpa, io, cmd, writer);
    }

    try writer.writeByte('\n');
    try writer.flush();
}

pub fn main(init: process.Init) !void {
    log.info("Starting benchmark...", .{});

    const arena = init.arena.allocator();
    const io = init.io;
    try bench(arena, io, "./zig-out/bin");

    log.info("Finished!", .{});
}
