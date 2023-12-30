const std = @import("std");
const sin = std.math.sin;
const cos = std.math.cos;
const asin = std.math.asin;
const sqrt = std.math.sqrt;

pub const earth_radius_km = 6372.8;

fn square(a: f64) f64 {
    return (a * a);
}

fn radiansFromDegrees(degrees: f64) f64 {
    return 0.01745329251994329577 * degrees;
}

// NOTE(casey): This is not meant to be a "good" way to calculate the Haversine
// distance. Instead, it attempts to follow, as closely as possible, the formula
// used in the real-world question on which these homework exercises are loosely
// based.

/// x values are in the range [-180,180] and y values in the range [-90,90]
pub fn referenceHaversine(x0: f64, y0: f64, x1: f64, y1: f64, earth_radius: f64) f64 {
    // std.debug.assert(x0 >= 0 and x1 <= 180 and y0 >= 0 and y1 <= 90);
    if (!(x0 >= -180 and x1 <= 180 and y0 >= -90 and y1 <= 90)) {
        std.debug.print("x0: {d}, y0: {d}, x1: {d}, y1: {d}\n", .{ x0, y0, x1, y1 });
    }
    var lat1: f64 = y0;
    var lat2: f64 = y1;
    const lon1: f64 = x0;
    const lon2: f64 = x1;

    const d_lon: f64 = radiansFromDegrees(lat2 - lat1);
    const d_lat: f64 = radiansFromDegrees(lon2 - lon1);
    lat1 = radiansFromDegrees(lat1);
    lat2 = radiansFromDegrees(lat2);
    const a: f64 = square(std.math.sin(d_lon / 2.0)) + cos(lat1) * cos(lat2) * square(sin(d_lat / 2));
    const c: f64 = 2.0 * asin(sqrt(a));

    const result: f64 = earth_radius * c;

    return result;
}

test "reference haversine" {
    const x0 = 0;
    const y0 = 0;
    const x1 = 0;
    const y1 = 90;

    const want: f64 = @floor((std.math.pi * earth_radius_km) / 2.0);

    const res = referenceHaversine(x0, y0, x1, y1, earth_radius_km);
    // std.debug.print("result: {d}\n", .{res});
    try std.testing.expectEqual(want, @floor(res));
}
