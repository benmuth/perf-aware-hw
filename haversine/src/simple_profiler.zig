const std = @import("std");
const print = std.debug.print;
const metrics = @import("platform_metrics.zig");

/// There should be one instance of Profiler per program to be profiled.
pub const Profiler = struct {
    os_clock_start: u64 = 0,
    os_clock_end: u64 = 0,

    cpu_clock_start: u64 = 0,
    cpu_clock_end: u64 = 0,

    est_cpu_freq: u64 = 0,

    counter: usize = 0,
    timings: [1024]u64,
    labels: [1024][]const u8,

    /// should be followed by endBlockProfile()
    /// any subsequent call to beginBlockProfile before an endBlockProfile
    /// will overwrite this call.
    pub fn beginBlockProfile(self: *Profiler, label: []const u8) void {
        self.labels[self.counter] = label;
        self.timings[self.counter] = metrics.readCPUTimer();
    }

    /// ends the most recently started block profile
    pub fn endBlockProfile(self: *Profiler) void {
        self.timings[self.counter] = metrics.readCPUTimer() - self.timings[self.counter];
        self.counter += 1;
        if (self.counter > self.timings.len) {
            self.counter = 0; // HACK: Silently wraps around because you can't return errors from defer statements
        }
    }

    pub fn beginProfiling(self: *Profiler) void {
        self.cpu_clock_start = metrics.readCPUTimer();
        self.os_clock_start = metrics.readOSTimer();
    }

    pub fn endProfiling(self: *Profiler) void {
        print("cpu end: {d}, cpu start: {d}\n", .{ self.cpu_clock_end, self.cpu_clock_start });
        self.os_clock_end = metrics.readOSTimer();
        self.cpu_clock_end = metrics.readCPUTimer();

        const os_time_elapsed = self.os_clock_end - self.os_clock_start;
        const cpu_time_elapsed = self.cpu_clock_end - self.cpu_clock_start;
        self.est_cpu_freq = metrics.estimateCPUFreq(cpu_time_elapsed, os_time_elapsed, metrics.getOSTimerFreq());
    }

    pub fn printReport(self: *Profiler) void {
        const total_elapsed = self.cpu_clock_end - self.cpu_clock_start;
        const total_time_ms = div(total_elapsed, self.est_cpu_freq) * 1000;
        print("Total time: {d:.4}ms (CPU Freq {d})\n", .{ total_time_ms, self.est_cpu_freq });
        for (self.timings, 0..) |timing, i| {
            if (timing == 0) {
                break;
            }
            print("  {s}: {d} ({d:.2}%)\n", .{ self.labels[i], timing, div(timing, total_elapsed) * 100 });
        }
    }
};

fn div(divisor: u64, dividend: u64) f64 {
    const divisorf: f64 = @floatFromInt(divisor);
    const dividendf: f64 = @floatFromInt(dividend);

    return divisorf / dividendf;
}

// fn testFn() void {
//     // const fn_info = @typeInfo(@TypeOf(testFn));
//     // print("");
//     // std.meta.declarationInfo(@TypeOf(testFn), );
//     // std.meta.declarationInfo(, )
// }

// test "test fn" {}
