const std = @import("std");
const print = std.debug.print;

const json = @import("json_parse.zig");
const haversine = @import("generate_data.zig");
const formula = @import("formula.zig");

// TODO: make this take other file names
fn readEntireFile(allocator: std.mem.Allocator, path: []const u8) !json.Buffer {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();

    var result = try json.Buffer.init(allocator, stat.size);

    const data = try allocator.alloc(u8, stat.size);

    const n = try file.read(data);

    print("{d} bytes read.\n", .{n});

    result.data = data;

    return result;
}

fn sumHaversineDistances(pairs: []haversine.Pair) f64 {
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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // const args = getArgs();

    var input_json = try readEntireFile(allocator, "./data/generated_points.json");
    defer input_json.deinit(allocator);

    const min_json_pair_encoding = 6 * 4;
    const max_pair_count = input_json.data.len / min_json_pair_encoding;

    // var parsed_values = try json.Buffer.init(allocator, @sizeOf(haversine.Pair) * max_pair_count);
    if (max_pair_count > 0) {
        const pairs = try allocator.alloc(haversine.Pair, max_pair_count * @sizeOf(haversine.Pair));
        defer allocator.free(pairs);

        if (pairs.len > 0) {
            const pair_count: u64 = try json.parseHaversinePairs(allocator, input_json, max_pair_count, pairs);
            print("parsed pairs: {d}\n", .{pair_count});
            // print("pairs: {any}\n", .{pairs[0..pair_count]});
            const sum: f64 = sumHaversineDistances(pairs[0..pair_count]);
            print("sum: {d}\n", .{sum});

            // if (args.check) {
            if (true) {
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
