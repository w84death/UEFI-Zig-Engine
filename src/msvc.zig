// MSVC runtime symbols for 32-bit UEFI

/// Unsigned long long remainder
export fn _aullrem(a: u64, b: u64) u64 {
    return @rem(a, b);
}

/// Unsigned long long division
export fn _aulldiv(a: u64, b: u64) u64 {
    return @divTrunc(a, b);
}

/// Signed long long remainder
export fn _allrem(a: i64, b: i64) i64 {
    return @rem(a, b);
}

/// Signed long long division
export fn _alldiv(a: i64, b: i64) i64 {
    return @divTrunc(a, b);
}

/// Floating point used flag
export fn __fltused() void {}
