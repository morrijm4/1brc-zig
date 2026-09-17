pub fn toFloat(i: i16) f32 {
    return @as(f32, @floatFromInt(i)) / 10;
}

pub fn toDigit(ch: u8) i16 {
    return ch - '0';
}

pub fn temperature(temp: []const u8) i16 {
    var result: i16 = 0;
    var i = temp.len - 1;

    const ones = toDigit(temp[i]);
    result = ones;

    i -= 2; // Skip '.'

    const tens = toDigit(temp[i]);
    result += tens * 10;

    // Edge Cases:
    // 1. -10.0
    // 2. -0.0
    // 3. 10.0
    // 4. 0.0

    if (temp.len == 5) {
        result += toDigit(temp[1]) * 100;
        result *= -1;
    } else if (temp.len == 4) {
        if (temp[0] == '-') {
            result *= -1;
        } else {
            result += toDigit(temp[0]) * 100;
        }
    }

    return result;
}
