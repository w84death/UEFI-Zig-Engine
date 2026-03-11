// Simple LCG random number generator

var seed: u32 = 12345;

pub fn init(new_seed: u32) void {
    seed = new_seed;
}

pub fn random() u32 {
    seed = seed *% 1103515245 +% 12345;
    return (seed >> 16) & 0x7FFF;
}

pub fn randomU8(max: u8) u8 {
    return @intCast(random() % @as(u32, max));
}

pub fn getSeed() u32 {
    return seed;
}

pub fn setSeed(new_seed: u32) void {
    seed = new_seed;
}

pub fn generateSeedFromPos(x: i32, y: i32) u32 {
    return @as(u32, @intCast(x)) *% 12345 +% @as(u32, @intCast(y)) *% 67890 +% seed;
}
