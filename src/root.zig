pub const jobs = 12;

// Keep at 128 bytes to fit in cache line.
pub const Stats = struct {
    sum: i64,
    count: u32,
    min: i16,
    max: i16,
};
