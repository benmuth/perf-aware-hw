const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const haversine = @import("formula.zig");
const rand_gen = std.rand.DefaultPrng;

/// x and y are both in degrees. x is the longitude, y is the latitude.
/// x is in the range [-180,180], y is in the range [-90,90].
const Point = struct {
    x: f64,
    y: f64,
};

const Pair = struct {
    p1: Point,
    p2: Point,
};

// A cluster is a group of points on a sphere. clusters are squares on a spherical
// surface, defined by the location of their central point (in degrees) and the size
// of a side (in degrees).
const num_cluster_pairs: u64 = 1;
const cluster_size: f64 = 5.0;
const cluster_rad: f64 = cluster_size / 2.0;

// the total number of points is 2 * num_point_pairs
const num_point_pairs: u64 = 2;

const point_pairs_per_cluster = num_point_pairs / num_cluster_pairs;

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
    assert(num_point_pairs % num_cluster_pairs == 0);
    // print("{d}\n", .{cluster_size});
    // print("{d}\n", .{cluster_rad});
    // print("{d}\n", .{point_pairs_per_cluster});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // var buffer: [num_cluster_pairs + num_point_pairs]Pair = undefined;
    // var buffer: [buffer_size]u8 = undefined;
    // var fba = std.heap.FixedBufferAllocator.init(&buffer);
    // const allocator = fba.allocator();

    var prng = rand_gen.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    const clusters = try makeClusters(allocator, num_cluster_pairs, rand);
    var cluster_max_x: f64 = -200;
    var cluster_max_y: f64 = -200;
    var cluster_min_x: f64 = 200;
    var cluster_min_y: f64 = 200;
    for (clusters) |cluster| {
        // print("cluster: {any}\n", .{cluster});
        cluster_max_y = @max(cluster.p1.y, cluster_max_y);
        cluster_max_y = @max(cluster.p2.y, cluster_max_y);

        cluster_max_x = @max(cluster.p1.x, cluster_max_x);
        cluster_max_x = @max(cluster.p2.x, cluster_max_x);

        cluster_min_y = @min(cluster.p1.y, cluster_min_y);
        cluster_min_y = @min(cluster.p2.y, cluster_min_y);

        cluster_min_x = @min(cluster.p1.x, cluster_min_x);
        cluster_min_x = @min(cluster.p2.x, cluster_min_x);
    }
    print("clusters:\n", .{});
    print("x: min: {d}\tmax: {d}\n", .{ cluster_min_x, cluster_max_x });
    print("y: min: {d}\tmax: {d}\n", .{ cluster_min_y, cluster_max_y });

    const points = try makePoints(allocator, clusters, num_point_pairs, rand);

    // test to see if anything is out of bounds
    var point_max_x: f64 = -200;
    var point_max_y: f64 = -200;
    var point_min_x: f64 = 200;
    var point_min_y: f64 = 200;
    for (points) |point| {
        // print("point: {any}\n", .{point});
        point_max_y = @max(point.p1.y, point_max_y);
        point_max_y = @max(point.p2.y, point_max_y);

        point_max_x = @max(point.p1.x, point_max_x);
        point_max_x = @max(point.p2.x, point_max_x);

        point_min_y = @min(point.p1.y, point_min_y);
        point_min_y = @min(point.p2.y, point_min_y);

        point_min_x = @min(point.p1.x, point_min_x);
        point_min_x = @min(point.p2.x, point_min_x);
    }
    print("points:\n", .{});
    print("x: min: {d}\tmax: {d}\n", .{ point_min_x, point_max_x });
    print("y: min: {d}\tmax: {d}\n", .{ point_min_y, point_max_y });

    try writePointsToJSONFile(points);
}

fn writePointsToJSONFile(points: []Pair) !void {
    _ = points;
    // const out_file = try std.fs.cwd().openFile("./hw/haversine/data/generated_points.json", .{
    //     .mode = .write_only,
    // });
    const out_file = try std.fs.cwd().createFile("./data/generated_points.json", .{});
    // var dir_iter = std.fs.cwd().iterate();
    // const first = (try dir_iter.next()).?;

    const stat = try out_file.stat();
    // while(dir_iter.next()) |entry| {

    // }

    print("size: {d}\n", .{stat.size});
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    // var json_lines = std.ArrayList([]u8);
    // defer json_lines.deinit();

    // json_writer = json_lines.Writer

    // const json_start = "{\"pairs\":[ ";
    // const json_end = "]}";

    // const json = std.mem.concat(, , )

}

fn makePoints(allocator: std.mem.Allocator, clusters: []Pair, num_pairs: u64, rand: std.rand.Random) ![]Pair {
    const point_pairs = try allocator.alloc(Pair, num_pairs);

    for (clusters) |cluster| {
        // print("cluster: x1: {d}, y1: {d}, x2: {d}, y2: {d}\n", .{
        //     cluster.p1.x,
        //     cluster.p1.y,
        //     cluster.p2.x,
        //     cluster.p2.y,
        // });
        for (0..point_pairs_per_cluster) |j| {
            point_pairs[j] = Pair{
                .p1 = .{
                    .x = cluster.p1.x + ((rand.float(f64) - 0.5) * cluster_size),
                    .y = cluster.p1.y + ((rand.float(f64) - 0.5) * cluster_size),
                },
                .p2 = .{
                    .x = cluster.p2.x + ((rand.float(f64) - 0.5) * cluster_size),
                    .y = cluster.p2.y + ((rand.float(f64) - 0.5) * cluster_size),
                },
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
            .p1 = .{
                .x = rand.float(f64) * (-180 + cluster_rad),
                .y = blk: {
                    const y_cand = ((rand.float(f64) - 0.5) * 180);
                    const y = if (y_cand > 0) y_cand - cluster_rad else y_cand + cluster_rad;
                    break :blk y;
                },
            },
            .p2 = .{
                .x = rand.float(f64) * (180 - cluster_rad),
                .y = blk: {
                    const y_cand = ((rand.float(f64) - 0.5) * 180);
                    const y = if (y_cand > 0) y_cand - cluster_rad else y_cand + cluster_rad;
                    break :blk y;
                },
            },
        };
    }
    return clusters;
}

test "divide" {
    const a = 5;
    const b = 2;

    print("{d}\n", .{a / b});
}
