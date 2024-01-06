const std = @import("std");
const print = std.debug.print;

const json = @import("json_parse.zig");
const haversine = @import("generate_data.zig");
const formula = @import("formula.zig");

// TODO: make this take other file names
fn readEntireFile(allocator: std.mem.Allocator) !json.Buffer {
    const file = try std.fs.cwd().openFile("./data/generated_points.json", .{});
    defer file.close();

    const stat = try file.stat();

    var result = try json.Buffer.init(allocator, stat.size);

    const data = try allocator.alloc(u8, stat.size);

    const n = try file.read(data);

    print("{d} bytes read.", .{n});

    result.data = data.ptr;

    return result;
}

fn sumHaversineDistances(pairs: []haversine.Pair) f64 {
    var sum: f64 = 0;

    const weight: f64 = @as(f64, @floatFromInt(1)) / @as(f64, @floatFromInt(pairs.len));

    for (pairs) |pair| {
        const dist: f64 = formula.referenceHaversine(pair.x0, pair.y0, pair.x1, pair.y1, formula.earth_radius_km);
        sum += dist * weight;
    }

    return sum;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) print("GPA LEAKED!!\n", .{});
    }
    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var input_json = try readEntireFile(allocator);
    defer input_json.deinit(allocator);

    const min_json_pair_encoding = 6 * 4;
    const max_pair_count = input_json.count / min_json_pair_encoding;

    var parsed_values = try json.Buffer.init(allocator, @sizeOf(haversine.Pair) * max_pair_count);
    defer parsed_values.deinit(allocator);

    if (parsed_values.count > 0) {
        const bytes = parsed_values.data[0..parsed_values.count];
        const pairs: []haversine.Pair = @alignCast(std.mem.bytesAsSlice(haversine.Pair, bytes)); // BUG
        const pair_count: u64 = try json.parseHaversinePairs(allocator, input_json, max_pair_count, pairs.ptr);
        print("parsed pairs: {d}", .{pair_count});
        const sum: f64 = sumHaversineDistances(pairs);
        print("sum: {d}\n", .{sum});
    }
}

// fn bytesToPairs(allocator: std.mem.Allocator, bytes: []u8) []haversine.Pair {
//     var pairs = try allocator.alloc(haversine.Pair, bytes / 4);

//     std.mem.bytesAsSlice(haversine.Pair, bytes);
// }
