const std = @import("std");
const Io = std.Io;
const Allocator = Io.Allocator;
const Stats = @import("sub").Stats;

pub const Table = struct {
    table: []Entry,

    pub const Entry = struct {
        key: []const u8,
        hash: u64,
        stats: Stats,

        pub fn isEmpty(self: Entry) bool {
            return self.key.len == 0;
        }
    };

    pub fn init(table: []Entry) Table {
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

    pub fn get(self: Table, key: []const u8) *Entry {
        const hash = std.hash.Wyhash.hash(42, key);
        var i = hash % self.table.len;
        while (!self.table[i].isEmpty()) : (i = (i + 1) % self.table.len) {
            if (self.table[i].hash == hash) return &self.table[i];
        }
        self.table[i].hash = hash;
        return &self.table[i];
    }

    pub fn getHash(self: Table, hash: u64) *Entry {
        var i = hash % self.table.len;
        while (!self.table[i].isEmpty()) : (i = (i + 1) % self.table.len) {
            if (self.table[i].hash == hash) return &self.table[i];
        }
        self.table[i].hash = hash;
        return &self.table[i];
    }
};
