const std = @import("std");
const Io = std.Io;
const Stats = @import("sub").Stats;

const Table = struct {
    table: []Entry,

    const Entry = struct {
        key: []const u8,
        hash: u64,
        mutex: Io.Mutex,
        stats: Stats,

        fn isEmpty(self: Entry) bool {
            return self.key.len == 0;
        }
    };

    fn init(table: []Entry) Table {
        for (table) |*entry| {
            entry.key = &.{};
            entry.hash = 0;
            entry.mutex = .init;
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
