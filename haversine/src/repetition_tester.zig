const std = @import("std");
const print = std.debug.print;
const metrics = @import("platform_metrics.zig");

const Mode = enum {
    Uninitialized,
    Testing,
    Completed,
    Error,
};

const Results = struct {
    test_count: u64 = 0,
    total_time: u64 = 0,
    max_time: u64 = 0,
    min_time: u64 = 0,
};

pub const Tester = struct {
    target_processed_byte_count: u64 = 0,
    cpu_timer_freq: u64 = 0,
    try_for_time: u64 = 10,
    tests_started_at: u64 = 0,
    mode: Mode = Mode.Uninitialized,
    print_new_minimums: bool = true,
    open_block_count: u32 = 0,
    close_block_count: u32 = 0,
    time_accumulated_on_this_test: u64 = 0,
    bytes_accumulated_on_this_test: u64 = 0,
    results: Results = Results{},

    pub fn err(self: *Tester, comptime message: []const u8) void {
        self.mode = Mode.Error;
        const stderr = std.io.getStdErr();
        defer stderr.close();
        _ = stderr.write("ERROR: " ++ message ++ "\n") catch {
            print("failed to write to std err\n", .{});
        };
    }

    pub fn newTestWave(self: *Tester, target_processed_byte_count: u64, cpu_timer_freq: u64, seconds_to_try: u32) void {
        if (self.mode == Mode.Uninitialized) {
            self.mode = Mode.Testing;
            self.target_processed_byte_count = target_processed_byte_count;
            self.cpu_timer_freq = cpu_timer_freq;
            self.print_new_minimums = true;
            self.results.min_time = std.math.maxInt(u64);
        } else if (self.mode == Mode.Completed) {
            // reset
            self.mode = Mode.Testing;

            if (self.target_processed_byte_count != target_processed_byte_count) {
                self.err("target_processed_byte_count changed");
            }

            if (self.cpu_timer_freq != cpu_timer_freq) {
                self.err("cpu_timer_freq changed");
            }
        }

        self.try_for_time = seconds_to_try * cpu_timer_freq;
        self.tests_started_at = metrics.readCPUTimer();
    }

    pub fn beginTime(self: *Tester) void {
        self.open_block_count += 1;
        self.time_accumulated_on_this_test -%= metrics.readCPUTimer();
    }

    pub fn endTime(self: *Tester) void {
        self.close_block_count += 1;
        self.time_accumulated_on_this_test +%= metrics.readCPUTimer();
    }

    pub fn countBytes(self: *Tester, byte_count: u64) void {
        self.bytes_accumulated_on_this_test += byte_count;
    }

    pub fn isTesting(self: *Tester) bool {
        if (self.mode == Mode.Testing) {
            const current_time = metrics.readCPUTimer();

            if (self.open_block_count != 0) {
                if (self.open_block_count != self.close_block_count) {
                    self.err("Unbalanced BeginTime/EndTime");
                }

                if (self.open_block_count != self.close_block_count) {
                    self.err("Processed byte count mismatch");
                }

                if (self.mode == Mode.Testing) {
                    var results = &self.results;
                    const elapsed_time = self.time_accumulated_on_this_test;
                    results.test_count += 1;
                    results.total_time += elapsed_time;

                    if (results.max_time < elapsed_time) {
                        results.max_time = elapsed_time;
                    }

                    if (results.min_time > elapsed_time) {
                        results.min_time = elapsed_time;

                        self.tests_started_at = current_time;

                        if (self.print_new_minimums) {
                            printTime("Min", @floatFromInt(results.min_time), self.cpu_timer_freq, self.bytes_accumulated_on_this_test);
                            print("            \n", .{});
                        }
                    }

                    self.open_block_count = 0;
                    self.close_block_count = 0;
                    self.time_accumulated_on_this_test = 0;
                    self.bytes_accumulated_on_this_test = 0;
                }
            }

            if ((current_time - self.tests_started_at) > self.try_for_time) {
                self.mode = Mode.Completed;

                print("\t\t\t\t\t\t\t\t\n", .{});
                printResults(self.results, self.cpu_timer_freq, self.target_processed_byte_count);
            }
        }

        return (self.mode == Mode.Testing);
    }
};

fn secondsFromCPUTime(cpu_time: f64, cpu_timer_freq: f64) f64 {
    return cpu_time / cpu_timer_freq;
}

fn printTime(label: []const u8, cpu_time: f64, cpu_timer_freq: u64, byte_count: u64) void {
    print("{s}: {d:.0}", .{ label, cpu_time });
    if (cpu_timer_freq > 0) {
        const seconds = secondsFromCPUTime(cpu_time, @floatFromInt(cpu_timer_freq));
        print(" ({d}ms)", .{seconds * 1000.0});

        if (byte_count > 0) {
            const gigabyte = (1024.0 * 1024.0 * 1024.0);
            const best_bandwith = @as(f64, @floatFromInt(byte_count)) / (gigabyte * seconds);
            print(" {d}gb/s", .{best_bandwith});
        }
    }
}

fn printResults(results: Results, cpu_timer_freq: u64, byte_count: u64) void {
    printTime("Min", @floatFromInt(results.min_time), cpu_timer_freq, byte_count);
    print("\n", .{});

    printTime("Max", @floatFromInt(results.max_time), cpu_timer_freq, byte_count);
    print("\n", .{});

    if (results.test_count > 0) {
        printTime("Avg", @as(f64, @floatFromInt(results.total_time)) / @as(f64, @floatFromInt(results.test_count)), cpu_timer_freq, byte_count);
        print("\n", .{});
    }
}
