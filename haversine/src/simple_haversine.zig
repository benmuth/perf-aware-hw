const std = @import("std");
const print = std.debug.print;

const json = @import("json_parse.zig");
const haversine = @import("generate_data.zig");
const formula = @import("formula.zig");
// const metrics = @import("platform_metrics.zig");
const config = @import("config");
const profiler = @import("profiler");
const counter = profiler.GetCounter(.prof, 0);
const next = counter.next;
const Profiler = profiler.Profiler;

var prof = Profiler.init();
const p = &prof;

fn readEntireFile(allocator: std.mem.Allocator, path: []const u8) !json.Buffer {
    const b = p.beginBlock(@src().fn_name, counter.get(next()));
    defer p.endBlock(b);
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();

    var result = try json.Buffer.init(allocator, stat.size);

    // print("file size: {d}\n", .{stat.size});
    const data = try allocator.alloc(u8, stat.size);

    _ = try file.read(data);

    result.data = data;

    return result;
}

fn sumHaversineDistances(pairs: []haversine.Pair) f64 {
    const b = p.beginBlock(@src().fn_name, counter.get(next()));
    defer p.endBlock(b);
    // print("pairs sample: {any}\n", .{pairs[0..1]});
    var sum: f64 = 0;

    const weight: f64 = @as(f64, @floatFromInt(1)) / @as(f64, @floatFromInt(pairs.len));

    for (pairs) |pair| {
        const dist: f64 = formula.referenceHaversine(pair.x0, pair.y0, pair.x1, pair.y1, formula.earth_radius_km);
        sum += dist * weight;
    }

    return sum;
}

pub fn main() !void {
    // var profiler = Profiler{ .anchors = undefined };
    // const p = &profiler;
    p.beginProfiling();
    // const startup_start = metrics.readCPUTimer();
    // const os_time_start = metrics.readOSTimer();
    const b = p.beginBlock("set up", counter.get(next()));
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gp_allocator = gpa.allocator();

    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var arena = std.heap.ArenaAllocator.init(gp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // const startup_end = metrics.readCPUTimer();

    const args = getArgs();
    p.endBlock(b);

    // var input_json: json.Buffer = undefined;
    var input_json = try readEntireFile(allocator, "./data/generated_points_1000000.json");
    defer input_json.deinit(allocator);
    // const read_end = metrics.readCPUTimer();

    const min_json_pair_encoding = 6 * 4 + 8;
    const max_pair_count = input_json.data.len / min_json_pair_encoding;

    // var parsed_values = try json.Buffer.init(allocator, @sizeOf(haversine.Pair) * max_pair_count);
    if (max_pair_count > 0) {
        const b3 = p.beginBlock("misc", counter.get(next()));
        const buffer_size = max_pair_count * @sizeOf(haversine.Pair);
        const pairs = try allocator.alloc(haversine.Pair, buffer_size);
        defer allocator.free(pairs);
        p.endBlock(b3);

        if (pairs.len > 0) {
            // const setup_end = metrics.readCPUTimer();
            // p.beginBlockProfile("parseHaversinePairs");
            const pair_count = try json.parseHaversinePairs(allocator, input_json, max_pair_count, pairs, p);
            // p.endBlockProfile();

            // const parse_end = metrics.readCPUTimer();
            // p.beginBlockProfile("sumHaversineDistances");
            const sum = sumHaversineDistances(pairs[0..pair_count]);
            // p.endBlockProfile();
            // const sum_end = metrics.readCPUTimer();

            print("Input size: {d}\n", .{input_json.data.len});
            print("Pair count: {d}\n", .{pair_count});
            print("Haversine sum: {d}\n", .{sum});

            p.endProfiling();
            p.printReport();
            // const os_time_end = metrics.readOSTimer();
            // const output_end = metrics.readCPUTimer();

            // const os_time_elapsed = os_time_end - os_time_start;
            // const total_elapsed = output_end - startup_start;

            // const startup_elapsed = startup_end - startup_start;
            // const read_elapsed = read_end - startup_end;
            // const setup_elapsed = setup_end - read_end;
            // const parse_elapsed = parse_end - setup_end;
            // const sum_elapsed = sum_end - parse_end;
            // const output_elapsed = output_end - sum_end;

            // const cpu_freq = metrics.estimateCPUFreq(total_elapsed, metrics.getOSTimerFreq(), os_time_elapsed);
            // const total_time = div(total_elapsed, cpu_freq) * 1000;
            // print("Total time: {d:.4}ms (CPU Freq {d})\n", .{ total_time, cpu_freq });
            // print("  Startup: {d} ({d:.2}%)\n", .{ startup_elapsed, div(startup_elapsed, total_elapsed) * 100 });
            // print("  Read: {d} ({d:.2}%)\n", .{ read_elapsed, div(read_elapsed, total_elapsed) * 100 });
            // print("  Setup: {d} ({d:.2}%)\n", .{ setup_elapsed, div(setup_elapsed, total_elapsed) * 100 });
            // print("  Parse: {d} ({d:.2}%)\n", .{ parse_elapsed, div(parse_elapsed, total_elapsed) * 100 });
            // print("  Sum: {d} ({d:.2}%)\n", .{ sum_elapsed, div(sum_elapsed, total_elapsed) * 100 });
            // print("  Output: {d} ({d:.2}%)\n", .{ output_elapsed, div(output_elapsed, total_elapsed) * 100 });

            // const total_sum = startup_elapsed + read_elapsed + setup_elapsed + parse_elapsed + sum_elapsed + output_elapsed;
            // print("cycle diff: {d}\n", .{total_elapsed - total_sum});

            if (args.check) {
                // if (true) {
                var answersf64 = try readEntireFile(allocator, "./data/haversines.f64");
                defer answersf64.deinit(allocator);

                if (answersf64.data.len > @sizeOf(f64)) {
                    const answer_values = std.mem.bytesAsSlice(f64, answersf64.data);

                    print("\nValidation:\n", .{});

                    const ref_answer_count = (answersf64.data.len - @sizeOf(f64)) / @sizeOf(f64);

                    if (pair_count != ref_answer_count) {
                        print("FAILED - pair count doesn't match {d}.\n", .{ref_answer_count});
                    }

                    const ref_sum = answer_values[ref_answer_count];
                    print("Reference sum: {d}\n", .{ref_sum});
                    print("Difference: {d}\n", .{sum - ref_sum});
                    print("\n", .{});
                }
            }
        }
    } else {
        print("ERROR: Malformed input JSON\n", .{});
    }
}

fn getArgs() Args {
    const usage = "usage: main [flag] \n-flag: pass the -c flag to automatically check the difference of the calculated haversine distance vs the expected distance";
    var arg_iter = std.process.args();
    if (!arg_iter.skip()) {
        print("{s}\n", .{usage});
    }
    const flag = arg_iter.next() orelse {
        return Args{ .check = false };
    };

    return Args{ .check = std.mem.eql(u8, flag, "-c") };

    // if (!(std.mem.eql(u8, "generate", command) or std.mem.eql(u8, "calculate", command))) {
    //     print("{s}\n", .{usage});
    //     return error.InvalidArg;
    // }

    // return Args{ .command = command };

}

const Args = struct { check: bool };

test "builtin" {
    const loc = @src();
    print("function: {s}\n", .{loc.fn_name});
}
