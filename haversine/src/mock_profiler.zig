const print = @import("std").debug.print;
const metrics = @import("platform_metrics.zig");

pub const Profiler = struct {
    os_clock_start: u64 = 0,
    os_clock_elapsed: u64 = 0,

    cpu_clock_start: u64 = 0,
    cpu_clock_elapsed: u64 = 0,

    est_cpu_freq: u64 = 0,

    pub fn init() Profiler {
        return Profiler{};
    }

    pub const Anchor = struct {};

    pub fn beginBlock(self: Profiler, label: []const u8, comptime counter: comptime_int) Block {
        _ = label;
        _ = self;
        _ = counter;
        return Block{};
    }

    pub fn endBlock(self: Profiler, block: Block) void {
        _ = self;
        _ = block;
    }

    const Block = struct {};

    pub fn beginProfiling(self: *Profiler) void {
        self.cpu_clock_start = metrics.readCPUTimer();
        self.os_clock_start = metrics.readOSTimer();
    }

    pub fn endProfiling(self: *Profiler) void {
        self.os_clock_elapsed = metrics.readOSTimer() - self.os_clock_start;
        self.cpu_clock_elapsed = metrics.readCPUTimer() - self.cpu_clock_start;

        self.est_cpu_freq = metrics.estimateCPUFreq(self.cpu_clock_elapsed, self.os_clock_elapsed, metrics.getOSTimerFreq());
    }

    pub fn printReport(self: Profiler) void {
        const total_time_ms = div(self.cpu_clock_elapsed, self.est_cpu_freq) * 1000;
        print("Total time: {d:.4}ms (CPU Freq {d})\n", .{ total_time_ms, self.est_cpu_freq });
    }

    fn printTimeElapsed(self: Profiler) void {
        _ = self;
    }
};

fn div(divisor: u64, dividend: u64) f64 {
    const divisorf: f64 = @floatFromInt(divisor);
    const dividendf: f64 = @floatFromInt(dividend);
    return divisorf / dividendf;
}

pub fn GetCounter(comptime scope: anytype, comptime starting_value: comptime_int) type {
    // Everytime the `GetCounter` function is given the same scope, it returns the same struct
    _ = scope;
    return create: {
        comptime var current_value: comptime_int = starting_value;
        break :create struct {
            // "Due to comptime memoization, counter.get() will only increment the counter if the
            // argument given is something it hasn’t seen before"
            // the pointer parameter helps with unique values
            pub fn get(comptime inc: *const i8) comptime_int {
                current_value += inc.*;
                return current_value;
            }

            /// pass this to get
            pub fn next() *const i8 {
                comptime var inc: i8 = 1;
                // return a pointer to be used as a unique value for get()
                return &inc;
            }
        };
    };
}
