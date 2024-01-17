const std = @import("std");
const print = std.debug.print;

const json = @import("json_parse.zig");
const haversine = @import("generate_data.zig");
const formula = @import("formula.zig");
const config = @import("config");
const profiling = @import("profiling");
const counter = profiling.GetCounter(.prof, 0);
const next = counter.next;
const profiler = profiling.profiler;

fn readEntireFile(allocator: std.mem.Allocator, path: []const u8) !json.Buffer {
    const b = profiler.beginBlock(@src().fn_name, counter.get(next()));
    defer profiler.endBlock(b);
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();

    var result = try json.Buffer.init(allocator, stat.size);

    const data = try allocator.alloc(u8, stat.size);

    _ = try file.read(data);

    result.data = data;

    return result;
}

fn sumHaversineDistances(pairs: []haversine.Pair) f64 {
    const b = profiler.beginBlock(@src().fn_name, counter.get(next()));
    defer profiler.endBlock(b);
    var sum: f64 = 0;

    const weight: f64 = @as(f64, @floatFromInt(1)) / @as(f64, @floatFromInt(pairs.len));

    for (pairs) |pair| {
        const dist: f64 = formula.referenceHaversine(pair.x0, pair.y0, pair.x1, pair.y1, formula.earth_radius_km);
        sum += dist * weight;
    }

    return sum;
}

pub fn main() !void {
    profiler.beginProfiling();
    const b = profiler.beginBlock("set up", counter.get(next()));
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gp_allocator = gpa.allocator();

    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var arena = std.heap.ArenaAllocator.init(gp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = getArgs();
    profiler.endBlock(b);

    var input_json = try readEntireFile(allocator, "./data/generated_points_3000000.json");
    defer input_json.deinit(allocator);

    const min_json_pair_encoding = 6 * 4 + 8;
    const max_pair_count = input_json.data.len / min_json_pair_encoding;

    if (max_pair_count > 0) {
        const b3 = profiler.beginBlock("misc", counter.get(next()));
        const buffer_size = max_pair_count * @sizeOf(haversine.Pair);
        const pairs = try allocator.alloc(haversine.Pair, buffer_size);
        defer allocator.free(pairs);
        profiler.endBlock(b3);

        if (pairs.len > 0) {
            const pair_count = try json.parseHaversinePairs(allocator, input_json, max_pair_count, pairs);

            const sum = sumHaversineDistances(pairs[0..pair_count]);

            print("Input size: {d}\n", .{input_json.data.len});
            print("Pair count: {d}\n", .{pair_count});
            print("Haversine sum: {d}\n", .{sum});

            profiler.endProfiling();
            profiler.printReport();
            if (args.check) {
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
}

const Args = struct { check: bool };

test "builtin" {
    const loc = @src();
    print("function: {s}\n", .{loc.fn_name});
}
