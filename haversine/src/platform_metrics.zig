const std = @import("std");

pub fn main() !void {
    // listing 73
    var args = std.process.args();
    _ = args.skip();
    const ms_to_wait_str = args.next() orelse "1_000";
    const ms_to_wait = try std.fmt.parseInt(u64, ms_to_wait_str, 10);

    const os_freq = getOSTimerFreq();
    std.debug.print("\n\tOS Freq: {d}\n", .{os_freq});

    const cpu_start = readCPUTimer();
    const os_start = readOSTimer();
    var os_end: u64 = 0;
    var os_elapsed: u64 = 0;
    const os_wait_time = os_freq * ms_to_wait / 1000;
    while (os_elapsed < os_wait_time) {
        os_end = readOSTimer();
        os_elapsed = os_end - os_start;
    }

    const cpu_end = readCPUTimer();
    const cpu_elapsed = cpu_end - cpu_start;
    const cpu_freq = os_freq * cpu_elapsed / os_elapsed;

    std.debug.print("\tOS Timer: {d} -> {d} = {d} elapsed\n", .{ os_start, os_end, os_elapsed });
    std.debug.print(" OS Seconds: {d:.4}\n", .{@as(f64, @floatFromInt(os_elapsed)) / @as(f64, @floatFromInt(os_freq))});

    std.debug.print("  CPU Timer: {d} -> {d} = {d} elapsed\n", .{ cpu_start, cpu_end, cpu_elapsed });
    std.debug.print("\tCPU Freq: {d:.4} (guessed)\n", .{cpu_freq});
}

pub fn estimateCPUFreq(cpu_time_elapsed: u64, os_time_elapsed: u64, os_freq: u64) u64 {
    return os_freq * cpu_time_elapsed / os_time_elapsed;
}

pub fn getOSTimerFreq() u64 {
    return 1_000_000_000;
}

/// returns timestamp in ns
pub fn readOSTimer() u64 {
    const now = std.time.Instant.now() catch return 0;
    const value: std.os.timespec = now.timestamp;

    const result: u64 = getOSTimerFreq() * @as(u64, @intCast(value.tv_sec)) + @as(u64, @intCast(value.tv_nsec));
    return result;
}

pub fn readCPUTimer() u64 {
    return rdtsc();
}

/// Read Time-Stamp Counter
fn rdtsc() u64 {
    var lo: u32 = undefined;
    var hi: u32 = undefined;

    asm volatile (
        \\rdtsc
        : [_] "={eax}" (lo),
          [_] "={edx}" (hi),
        :
        : "memory"
    );

    return (@as(u64, hi) << 32) | @as(u64, lo);
}

test "os timer" {
    // listing 71
    const os_freq = getOSTimerFreq();
    std.debug.print("\n\tOS Freq: {d}\n", .{os_freq});

    const os_start = readOSTimer();
    var os_end: u64 = 0;
    var os_elapsed: u64 = 0;
    while (os_elapsed < os_freq) {
        os_end = readOSTimer();
        os_elapsed = os_end - os_start;
    }

    std.debug.print("\tOS Timer: {d} -> {d} = {d} elapsed\n", .{ os_start, os_end, os_elapsed });
    std.debug.print(" OS Seconds: {d:.4}\n", .{@as(f64, @floatFromInt(os_elapsed)) / @as(f64, @floatFromInt(os_freq))});
}

test "cpu timer" {
    // listing 72
    const os_freq = getOSTimerFreq();
    std.debug.print("\n\tOS Freq: {d}\n", .{os_freq});

    const cpu_start = readCPUTimer();
    const os_start = readOSTimer();
    var os_end: u64 = 0;
    var os_elapsed: u64 = 0;
    while (os_elapsed < os_freq) {
        os_end = readOSTimer();
        os_elapsed = os_end - os_start;
    }

    const cpu_end = readCPUTimer();
    const cpu_elapsed = cpu_end - cpu_start;

    std.debug.print("\tOS Timer: {d} -> {d} = {d} elapsed\n", .{ os_start, os_end, os_elapsed });
    std.debug.print(" OS Seconds: {d:.4}\n", .{@as(f64, @floatFromInt(os_elapsed)) / @as(f64, @floatFromInt(os_freq))});

    std.debug.print("  CPU Timer: {d} -> {d} = {d} elapsed\n", .{ cpu_start, cpu_end, cpu_elapsed });
}
