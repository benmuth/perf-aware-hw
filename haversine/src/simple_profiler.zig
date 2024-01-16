const std = @import("std");
const print = std.debug.print;
const metrics = @import("platform_metrics.zig");

// comptime stuff, seehttps://ziggit.dev/t/c-c-macro-challenge-1-boost-pp-counter/2235/5 and https://ziggit.dev/t/understanding-arbitrary-bit-width-integers/2028/7
pub fn GetCounter(comptime scope: anytype, comptime starting_value: comptime_int) type {
    // "Due to comptime memoization, counter.get() will only increment the counter if the argument given is something it hasn’t seen before"
    // so the counter is grouped by the 'scope' variable
    _ = scope;
    return create: {
        comptime var current_value: comptime_int = starting_value;
        break :create struct {
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

            // pub fn previous() *const i8 {
            //     comptime var inc: i8 = -1;
            //     return &inc;
            // }

            // pub fn current() *const i8 {
            //     comptime var inc: i8 = 0;
            //     return &inc;
            // }
        };
    };
}
// pub fn counter() comptime_int {
//     // comptime {
//     comptime var i = 0;
//     comptime {
//         const S = struct {
//             var counter: comptime_int = 0;
//         };
//         S.counter += 1;
//         i = S.counter;
//     }

//     return i;
//     // }
// }

const num_anchors = 4096;

/// There should be one instance of Profiler per program to be profiled.
pub const Profiler = struct {
    os_clock_start: u64 = 0,
    os_clock_elapsed: u64 = 0,

    cpu_clock_start: u64 = 0,
    cpu_clock_end: u64 = 0,

    est_cpu_freq: u64 = 0,

    // TODO: This should be comptime only
    // comptime counter: comptime_int = 0,
    anchors: [num_anchors]Anchor,
    // timings: [1024]u64,
    // labels: [1024][]const u8,
    parent_block: usize = 0,

    // HACK: this is clumsy, consolidate this and Block.beginProfile
    // pub fn startBlock(self: *Profiler, label: []const u8, index: usize) Block {
    //     const parent_index = self.parent_block;
    //     self.parent_block = index;

    //     // return Block.begin(block_name, index, parent_index, self.anchors[index].elapsed_inclusive);
    //     return Block{
    //         .start = metrics.readCPUTimer(),
    //         .label = label,
    //         .anchor_index = index,
    //         .parent_index = parent_index,
    //         // .old_elapsed_inclusive = old_elapsed_inclusive,
    //     };
    // }

    pub fn init() Profiler {
        return Profiler{
            .anchors = [_]Anchor{.{
                .elapsed = 0,
                // .elapsed_inclusive = 0,
                // .elapsed_exclusive = 0,
                .label = "",
                .elapsed_children = 0,
                .hit_count = 0,
            }} ** num_anchors,
        };
    }

    pub const Anchor = struct {
        elapsed: u64,
        elapsed_children: u64,
        hit_count: u64,
        label: []const u8,
    };

    // can pass @src().fn_name for label parameter when relevant
    pub fn beginBlock(self: *Profiler, comptime label: []const u8, index: usize) Block {
        const parent_index = self.parent_block;
        self.parent_block = index;
        return Block{
            .start = metrics.readCPUTimer(),
            .label = label,
            .anchor_index = index,
            .parent_index = parent_index,
            // .old_elapsed_inclusive = old_elapsed_inclusive,
        };
    }

    pub fn endBlock(self: *Profiler, block: Block) void {
        const elapsed = metrics.readCPUTimer() - block.start;
        self.parent_block = block.parent_index;

        const parent = &(self.anchors[block.parent_index]);
        parent.elapsed_children += elapsed;

        const anchor = &(self.anchors[block.anchor_index]);
        anchor.elapsed += elapsed;
        anchor.hit_count += 1;
        anchor.label = block.label;
    }

    const Block = struct {
        start: u64,
        label: []const u8,
        anchor_index: usize,
        parent_index: usize,
        // old_elapsed_inclusive: u64,

    };

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
        var percent_sum: f64 = 0.0;
        for (self.anchors[1..], 1..) |anchor, i| {
            if (anchor.label.len == 0) {
                continue;
            }
            print("index: {d}\n", .{i});
            percent_sum += printTimeElapsed(anchor, total_elapsed);
            // _ = printTimeElapsed(anchor, total_elapsed);
            // print("sum: {d}\n", .{percent_sum});
            // const percent = div(self.anchors[i].elapsed, total_elapsed) * 100;
            // percent_sum += percent;
            // print("  {s}: {d} ({d:.2}%)\n", .{ self.anchors[i].label, self.anchors[i].elapsed, percent });
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
            const percent_with_children = div(anchor.elapsed, total_elapsed) * 100;
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
