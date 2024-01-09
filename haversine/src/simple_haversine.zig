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

    print("{d} bytes read.\n", .{n});

    result.data = data.ptr;

    return result;
}

fn sumHaversineDistances(pairs: []haversine.Pair) f64 {
    print("pairs sample: {any}\n", .{pairs[0..1]});
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

    // var parsed_values = try json.Buffer.init(allocator, @sizeOf(haversine.Pair) * max_pair_count);
    const pairs = try allocator.alloc(haversine.Pair, max_pair_count * @sizeOf(haversine.Pair));
    defer allocator.free(pairs);

    if (pairs.len > 0) {
        // const bytes = pairs.data[0..pairs.count];
        // print("bytes: \n{any}\n", .{bytes[0..128]});
        // var test_pairs = try allocator.alloc(haversine.Pair, bytes.len / 32);

        // print("test_pairs type: {any}\n", .{@TypeOf(test_pairs)});
        // print("test_pairs align: {any}\n", .{@alignOf(@TypeOf(test_pairs))});

        // test_pairs.ptr = @ptrCast(bytes);
        // test_pairs.len = bytes.len / 4;
        // for (@as(*align(1)))
        // print("bytes type: {any}\n", .{@TypeOf(bytes)});
        // print("bytes align: {any}\n", .{@alignOf(@TypeOf(bytes))});
        // const aligned_bytes = @as([]align(8) u8, @alignCast(bytes));
        // print("aligned_bytes type: {any}\n", .{@TypeOf(aligned_bytes)});
        // print("aligned_bytes align: {any}\n", .{@alignOf(@TypeOf(aligned_bytes))});
        // const pairs = std.mem.bytesAsSlice(haversine.Pair, bytes);
        // print("pairs type: {any}\n", .{@TypeOf(pairs)});
        // print("pairs align: {any}\n", .{@alignOf(@TypeOf(pairs))});
        // print("haversine pair align: {any}\n", .{@alignOf(haversine.Pair)});
        // const aligned_pairs =
        // const pairs: []haversine.Pair = std.mem.bytesAsSlice(haversine.Pair, @as([]align(8) u8, @alignCast(bytes))); // BUG
        const pair_count: u64 = try json.parseHaversinePairs(allocator, input_json, max_pair_count, pairs);
        print("parsed pairs: {d}\n", .{pair_count});
        const sum: f64 = sumHaversineDistances(@alignCast(pairs));
        print("sum: {d}\n", .{sum});
    }
}

fn bytesToPairs(allocator: std.mem.Allocator, bytes: []u8) []haversine.Pair {
    var pairs = try allocator.alloc(haversine.Pair, bytes / 32);

    var i: usize = 0;
    while (i < bytes.len) : (i += 32) {
        // NOTE: wrong endianess?
        const x0 = std.mem.bytesAsValue(f64, bytes[i .. i + 8]);
        const y0 = std.mem.bytesAsValue(f64, bytes[i + 8 .. i + 16]);
        const x1 = std.mem.bytesAsValue(f64, bytes[i + 16 .. i + 24]);
        const y1 = std.mem.bytesAsValue(f64, bytes[i + 24 .. i + 32]);
        pairs[i / 32] = .{ .x0 = x0.*, .y0 = y0.*, .x1 = x1.*, .y1 = y1.* };
    }

    return pairs;
    // std.mem.bytesAsSlice(haversine.Pair, bytes);
}

test "bytes to pairs" {
    // bytes =
}

test "ptr cast" {
    const pairs = [_]haversine.Pair{.{ .x0 = 2.0, .y0 = 4.0, .x1 = 1.6, .y1 = 6.2 }} ** 4;
    const pair_buf = pairs[0..];
    print("pair_buf type: {any}\n", .{@TypeOf(pair_buf)});
    print("pair_buf align: {any}\n", .{@alignOf(@TypeOf(pair_buf))});

    const bytes = std.mem.sliceAsBytes(pair_buf);
    print("bytes type: {any}\n", .{@TypeOf(bytes)});
    print("bytes align: {any}\n", .{@alignOf(@TypeOf(bytes))});

    // out_buf = std.
    pair_buf.ptr = @ptrCast(bytes.ptr);
    pair_buf.len = bytes.len / 4;
    // for (@(pair_buf)) |pair| {}
}

test "align" {
    const pairs = [_]haversine.Pair{.{ .x0 = 2.0, .y0 = 4.0, .x1 = 1.6, .y1 = 6.2 }} ** 4;
    const buf = pairs[0..];

    const bytes = std.mem.sliceAsBytes(buf);
    print("bytes type: {any}\n", .{@TypeOf(bytes)});
    print("bytes align: {any}\n", .{@alignOf(@TypeOf(bytes))});

    const converted_pairs = std.mem.bytesAsSlice(haversine.Pair, bytes);
    print("converted_pairs type: {any}\n", .{@TypeOf(converted_pairs)});
    print("converted_pairs align: {any}\n", .{@alignOf(@TypeOf(converted_pairs))});

    // print("buf: {any}\n", .{buf});
    print("len: {d}\n", .{buf.len});

    print("bytes type: {any}\n", .{@TypeOf(bytes)});
    print("converted_pairs type: {any}\n", .{@TypeOf(converted_pairs)});
    for (converted_pairs) |pair| {
        print("x0: {d}, y0: {d}, x1: {d}, y1: {d}\n", .{ pair.x0, pair.y0, pair.x1, pair.y1 });
    }
}
