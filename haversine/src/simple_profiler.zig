const std = @import("std");
const print = std.debug.print;
const metrics = @import("platform_metrics.zig");

const num_anchors = 4096;

/// There should be one instance of Profiler per program to be profiled.
pub const Profiler = struct {
    os_clock_start: u64 = 0,
    os_clock_elapsed: u64 = 0,

    cpu_clock_start: u64 = 0,
    cpu_clock_elapsed: u64 = 0,

    est_cpu_freq: u64 = 0,

    anchors: [num_anchors]Anchor,
    global_parent_index: usize = 0,

    pub fn init() Profiler {
        return Profiler{
            .anchors = [_]Anchor{.{
                .elapsed = 0,
                .label = "",
                .elapsed_children = 0,
                .hit_count = 0,
                .elapsed_at_root = 0,
            }} ** num_anchors,
        };
    }

    pub const Anchor = struct {
        elapsed: u64,
        elapsed_children: u64,
        hit_count: u64,
        label: []const u8,
        elapsed_at_root: u64,
    };

    // can pass @src().fn_name for label parameter when relevant
    pub fn beginBlock(self: *Profiler, comptime label: []const u8, index: usize) Block {
        const parent_index = self.global_parent_index;
        self.global_parent_index = index;
        return Block{
            .start = metrics.readCPUTimer(),
            .label = label,
            .anchor_index = index,
            .parent_index = parent_index,
            .old_elapsed_at_root = self.anchors[index].elapsed_at_root,
        };
    }

    pub fn endBlock(self: *Profiler, block: Block) void {
        const elapsed = metrics.readCPUTimer() - block.start;
        self.global_parent_index = block.parent_index;

        const parent = &(self.anchors[block.parent_index]);
        parent.elapsed_children += elapsed;

        const anchor = &(self.anchors[block.anchor_index]);
        anchor.elapsed += elapsed;
        anchor.hit_count += 1;
        anchor.label = block.label;
        anchor.elapsed_at_root = block.old_elapsed_at_root + elapsed;
    }

    const Block = struct {
        start: u64,
        label: []const u8,
        anchor_index: usize,
        parent_index: usize,
        old_elapsed_at_root: u64,
    };

    pub fn beginProfiling(self: *Profiler) void {
        self.cpu_clock_start = metrics.readCPUTimer();
        self.os_clock_start = metrics.readOSTimer();
    }

    pub fn endProfiling(self: *Profiler) void {
        self.os_clock_elapsed = metrics.readOSTimer() - self.os_clock_start;
        self.cpu_clock_elapsed = metrics.readCPUTimer() - self.cpu_clock_start;

        self.est_cpu_freq = metrics.estimateCPUFreq(self.cpu_clock_elapsed, self.os_clock_elapsed, metrics.getOSTimerFreq());
    }

    pub fn printReport(self: *Profiler) void {
        const total_time_ms = div(self.cpu_clock_elapsed, self.est_cpu_freq) * 1000;
        print("Total time: {d:.4}ms (CPU Freq {d})\n", .{ total_time_ms, self.est_cpu_freq });
        var percent_sum: f64 = 0.0;
        for (self.anchors[1..], 1..) |anchor, i| {
            if (anchor.label.len == 0) {
                continue;
            }
            print("index: {d}\n", .{i});
            percent_sum += printTimeElapsed(anchor, self.cpu_clock_elapsed);
        }
        print("Profile coverage: {d:.2}%\n", .{percent_sum});
    }

    fn printTimeElapsed(anchor: Profiler.Anchor, total_elapsed: u64) f64 {
        const elapsed = anchor.elapsed -% anchor.elapsed_children;
        const percent = div(elapsed, total_elapsed) * 100;
        print("  {s}[{d}]: {d} ({d:.2}%", .{
            anchor.label,
            anchor.hit_count,
            elapsed,
            percent,
        });
        if (anchor.elapsed_children != 0) {
            const percent_with_children = div(anchor.elapsed_at_root, total_elapsed) * 100;
            print(", {d:.2}% w/children", .{percent_with_children});
        }
        print(")\n", .{});
        return percent;
    }
};

fn div(divisor: u64, dividend: u64) f64 {
    const divisorf: f64 = @floatFromInt(divisor);
    const dividendf: f64 = @floatFromInt(dividend);
    return divisorf / dividendf;
}

// comptime stuff, see https://ziggit.dev/t/c-c-macro-challenge-1-boost-pp-counter/2235/5 and https://ziggit.dev/t/understanding-arbitrary-bit-width-integers/2028/7
// NOTE: This is slated to break in the future. See https://github.com/ziglang/zig/issues/7396
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
