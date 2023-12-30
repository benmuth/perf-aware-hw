const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const formula = @import("formula.zig");
const rand_gen = std.rand.DefaultPrng;

/// x and y are both in degrees. x is the longitude, y is the latitude.
/// x is in the range [-180,180], y is in the range [-90,90].
// const Point = struct {
//     x: f64,
//     y: f64,
// };

const Pair = struct {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
};

// A cluster is a group of points on a sphere. clusters are squares on a spherical
// surface, defined by the location of their central point (in degrees) and the size
// of a side (in degrees).
// const num_cluster_pairs: u64 = 1;
const cluster_size: f64 = 5.0;
const cluster_rad: f64 = cluster_size / 2.0;

// the total number of points is 2 * num_point_pairs
// const num_point_pairs: u64 = 1_000;

// const point_pairs_per_cluster = num_point_pairs / num_cluster_pairs;

// const buffer_size = @sizeOf(Pair) * (num_cluster_pairs + num_point_pairs);

// const clusters: []const Pair = clusters: {
//     var result: [num_cluster_pairs]Pair = undefined;
//     for (0..num_cluster_pairs) |i| {
//         result[i] = .{
//             .p1 = .{ .x = 0, .y = 0 },
//             .p2 = .{ .x = 0, .y = 0 },
//         };
//     }
//     break :clusters &result;
// };

pub fn main() !void {
    const args = try getArgs();
    // if (std.mem.eql(u8, "generate", args.command)) {
    try generateTestData(args.seed, args.n_clusters, args.n_points);
    // } else {
    //     print("not implemented!\n", .{});
    // }
}

fn generateTestData(input_seed: ?u64, num_clusters: u64, num_points: u64) !void {
    const start = try std.time.Instant.now();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var seed: u64 = undefined;
    if (input_seed != null) {
        seed = input_seed.?;
    } else {
        try std.os.getrandom(std.mem.asBytes(&seed));
    }
    var prng = rand_gen.init(seed);
    const rand = prng.random();

    const clusters = try makeClusters(allocator, num_clusters, rand);
    const points = try makePoints(allocator, clusters, num_points, rand);
    const mid = try std.time.Instant.now();
    const n = try writePointsToJSONFile(allocator, points);
    const end = try std.time.Instant.now();

    const gen_duration: f64 = @floatFromInt(mid.since(start));
    const gen_points_seconds: f64 = gen_duration / 1_000_000_000.0;
    const write_duration: f64 = @floatFromInt(end.since(mid));
    const write_points_seconds: f64 = write_duration / 1_000_000_000.0;
    print("time to generate points: {d:0<.3}s\n", .{gen_points_seconds});
    print("time to write points: {d:0<.3}s\n", .{write_points_seconds});
    print("total time: {d:0<.3}s\n", .{gen_points_seconds + write_points_seconds});

    print("{d}MB written\n", .{n / 1_000_000});

    const m = try writePointData(allocator, points, seed, num_clusters);
    print("{d} bytes written\n", .{m});
}

fn writePointsToJSONFile(allocator: std.mem.Allocator, points: []Pair) !u64 {
    const out_file = try std.fs.cwd().createFile("./data/generated_points.json", .{});
    defer out_file.close();

    var buffer = std.ArrayList(u8).init(allocator);
    var buffered_writer = std.io.bufferedWriter(buffer.writer());

    _ = try buffered_writer.write("{\"pairs\":[");

    for (points, 0..) |point, i| {
        var line = try std.fmt.allocPrint(allocator, "{{\"x0\":{d},\"y0\":{d},\"y1\":{d},\"y1\":{d} }},", .{ point.x0, point.y0, point.x1, point.y1 });

        if (i == points.len - 1) {
            line = try std.fmt.allocPrint(allocator, "{{\"x0\":{d},\"y0\":{d},\"y1\":{d},\"y1\":{d} }}", .{ point.x0, point.y0, point.x1, point.y1 });
        }
        _ = try buffered_writer.write(line);
    }

    _ = try buffered_writer.write("]}");
    try buffered_writer.flush();

    return try out_file.write(buffer.items);
}

fn makePoints(allocator: std.mem.Allocator, clusters: []Pair, num_pairs: u64, rand: std.rand.Random) ![]Pair {
    const point_pairs = try allocator.alloc(Pair, num_pairs);

    const point_pairs_per_cluster = num_pairs / clusters.len;
    for (clusters) |cluster| {
        for (0..point_pairs_per_cluster) |j| {
            point_pairs[j] = Pair{
                .x0 = cluster.x1 + ((rand.float(f64) - 0.5) * cluster_size),
                .y0 = cluster.y1 + ((rand.float(f64) - 0.5) * cluster_size),
                .x1 = cluster.x0 + ((rand.float(f64) - 0.5) * cluster_size),
                .y1 = cluster.y0 + ((rand.float(f64) - 0.5) * cluster_size),
            };
        }
    }
    return point_pairs;
}

/// creates num_pairs paired clusters
fn makeClusters(allocator: std.mem.Allocator, num_pairs: u64, rand: std.rand.Random) ![]Pair {
    const clusters = try allocator.alloc(Pair, num_pairs);
    // setting a pair of clusters to be on opposite hemispheres (x1:[-180:0],x2:[0:180])
    for (0..clusters.len) |i| {
        clusters[i] = Pair{
            // making sure point bounds aren't exceeded
            .x0 = rand.float(f64) * (180 - cluster_rad),
            .y0 = blk: {
                const y_cand = ((rand.float(f64) - 0.5) * 180);
                const y = if (y_cand > 0) y_cand - cluster_rad else y_cand + cluster_rad;
                break :blk y;
            },
            .x1 = rand.float(f64) * (-180 + cluster_rad),
            .y1 = blk: {
                const y_cand = ((rand.float(f64) - 0.5) * 180);
                const y = if (y_cand > 0) y_cand - cluster_rad else y_cand + cluster_rad;
                break :blk y;
            },
        };
    }
    return clusters;
}

fn writePointData(allocator: std.mem.Allocator, points: []Pair, seed: u64, num_clusters: u64) !u64 {
    // TODO: write these floats to a file for reference
    var haversines = try allocator.alloc(f64, points.len);
    var sum: f64 = 0;
    for (points, 0..) |pair, i| {
        const haversine = formula.referenceHaversine(pair.x0, pair.y0, pair.x1, pair.y1, formula.earth_radius_km);
        haversines[i] = haversine;
        sum += haversine;
    }

    const num_points: f64 = @floatFromInt(points.len);
    const mean = sum / num_points;

    const out_file = try std.fs.cwd().createFile("./data/point_data.txt", .{});
    const output = try std.fmt.allocPrint(allocator, "Method: cluster\nRandom seed: {d}\nPair count: {d}\nCluster count: {d}\nExpected sum: {d}\n", .{
        seed,
        points.len,
        num_clusters,
        mean,
    });
    print("{s}\n", .{output});
    const n = try out_file.write(output);

    const float_file = try std.fs.cwd().createFile("./data/haversines.f64", .{});
    // std.fmt.parseFloat(, )
    const haversine_string = try std.fmt.allocPrint(allocator, "{d}{d}", .{ haversines, mean });
    const m = try float_file.write(haversine_string);
    // var float_writer = float_file.writer();
    // float_writer.writeByte()

    return m + n;
}

fn getArgs() !Args {
    const usage = "usage: haversine [seed] [nclusters] [npoints]\n-seed: random seed\n-nclusters: number of point clusters to generate\n-npoints: number of point pairs to generate\nTo use a random seed use '-' as the seed value";
    var arg_iter = std.process.args();
    if (!arg_iter.skip()) {
        print("{s}\n", .{usage});
    }
    const seed = arg_iter.next() orelse {
        print("{s}\n", .{usage});
        return error.NoArgs;
    };
    const nclusters = arg_iter.next() orelse {
        print("{s}\n", .{usage});
        return error.NoArgs;
    };
    const npoints = arg_iter.next() orelse {
        print("{s}\n", .{usage});
        return error.NoArgs;
    };

    return Args{
        .seed = std.fmt.parseInt(u64, seed, 10) catch null,
        .n_clusters = try std.fmt.parseInt(u64, nclusters, 10),
        .n_points = try std.fmt.parseInt(u64, npoints, 10),
    };

    // if (!(std.mem.eql(u8, "generate", command) or std.mem.eql(u8, "calculate", command))) {
    //     print("{s}\n", .{usage});
    //     return error.InvalidArg;
    // }

    // return Args{ .command = command };
}

const Args = struct {
    seed: ?u64,
    n_clusters: u64,
    n_points: u64,
};
