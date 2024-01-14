const std = @import("std");
const print = std.debug.print;
const metrics = @import("platform_metrics.zig");

/// There should be one instance of Profiler per program to be profiled.
pub const Profiler = struct {
    os_clock_start: u64 = 0,
    os_clock_elapsed: u64 = 0,

    cpu_clock_start: u64 = 0,
    cpu_clock_end: u64 = 0,

    est_cpu_freq: u64 = 0,

    counter: usize = 0,
    anchors: [4096]Anchor,
    // timings: [1024]u64,
    // labels: [1024][]const u8,

    pub fn startBlock(self: *Profiler, block_name: []const u8) Block {
        self.counter += 1;
        return Block.beginProfile(block_name, self.counter);
    }

    pub fn init() Profiler {
        return Profiler{
            .anchors = [_]Anchor{.{ .start = 0, .elapsed = 0, .label = "" }} ** 4096,
        };
    }

    pub const Anchor = struct {
        start: u64,
        elapsed: u64,
        label: []const u8,
    };

    pub const Block = struct {
        start: u64,
        label: []const u8,
        anchor_index: usize,

        pub fn beginProfile(label: []const u8, index: usize) Block {
            return Block{
                .anchor_index = index,
                .label = label,
                .start = metrics.readCPUTimer(),
            };
        }

        pub fn endProfile(self: Block, profiler: *Profiler) void {
            // print("anchor index: {d}\n", .{self.anchor_index});
            const elapsed = metrics.readCPUTimer() - self.start;
            const anchor = &(profiler.anchors[self.anchor_index]);
            // print("anchor elapsed before: {d}\n", .{anchor.elapsed});
            anchor.elapsed = elapsed;
            anchor.label = self.label;
            // print("anchor elapsed after: {d}\n", .{anchor.elapsed});
        }
    };

    /// should be followed by endBlockProfile()
    /// any subsequent call to beginBlockProfile before an endBlockProfile
    /// will overwrite this call.
    // pub fn beginBlockProfile(self: *Profiler, label: []const u8, index: usize) void {
    //     self.counter += 1;
    //     self.anchors[index] = Anchor{
    //         .start = metrics.readCPUTimer(),
    //         .elapsed = 0,
    //         .label = label,
    //     };
    // }

    /// ends the most recently started block profile
    // pub fn endBlockProfile(self: *Profiler) void {
    //     self.anchors[self.counter].elapsed = metrics.readCPUTimer() - self.anchors[self.counter].start;
    //     if (self.counter > self.anchors.len) {
    //         self.counter = 0; // HACK: Silently wraps around because you can't return errors from defer statements
    //     }
    // }

    pub fn beginProfiling(self: *Profiler) void {
        self.cpu_clock_start = metrics.readCPUTimer();
        self.os_clock_start = metrics.readOSTimer();
    }

    pub fn endProfiling(self: *Profiler) void {
        self.os_clock_elapsed = metrics.readOSTimer() - self.os_clock_start;
        self.cpu_clock_end = metrics.readCPUTimer();

        // const os_time_elapsed = self.os_clock_end - self.os_clock_start;
        const cpu_time_elapsed = self.cpu_clock_end - self.cpu_clock_start;
        self.est_cpu_freq = metrics.estimateCPUFreq(cpu_time_elapsed, self.os_clock_elapsed, metrics.getOSTimerFreq());
    }

    pub fn printReport(self: *Profiler) void {
        const total_elapsed = self.cpu_clock_end - self.cpu_clock_start;
        const total_time_ms = div(total_elapsed, self.est_cpu_freq) * 1000;
        print("Total time: {d:.4}ms (CPU Freq {d})\n", .{ total_time_ms, self.est_cpu_freq });
        for (self.anchors[1..], 1..) |anchor, i| {
            if (anchor.label.len == 0) {
                break;
            }
            print("  {s}: {d} ({d:.2}%)\n", .{ self.anchors[i].label, self.anchors[i].elapsed, div(self.anchors[i].elapsed, total_elapsed) * 100 });
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

// test "test arrays" {
//     var ts = test_struct{ .a = .{1} ** 8 };
//     const pts = &ts;

//     const n = &(pts.a[0]);
//     n.* += 1;

//     try std.testing.expect(ts.a[0] == 2);
// }

// const test_struct = struct {
//     a: [8]u8,
// };
