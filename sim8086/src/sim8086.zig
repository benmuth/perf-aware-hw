const std = @import("std");
const print = @import("std").debug.print;
const decode = @import("decoding.zig");
const sim = @import("simulate.zig");

const resource_dir = "../../../perf-aware/resources/part1/";
const output_dir = "../../../perf-aware/hw/sim8086/output/";

// example usage for this program:
// zig-out/bin/sim8086 listing_0037_single_register_mov listing_0037_single_register_mov.asm

// given the name of a binary executable file as input, and the name of an output file to write to, disassembles the input file and writes the assembly to the output file

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try parseArgs(allocator);
    const data = try readInputFile(allocator, args.input);

    // TODO: refactor the instruction iterating out so that work isn't repeated between decode.decode and sim.simulate
    if (std.mem.eql(u8, args.command, "decode")) {
        var assembly = try decode.decode(allocator, data);
        defer assembly.deinit();
        const output = try addHeader(allocator, args.input, assembly.items);

        print("output:\n{s}\n", .{output});
        const stdout_file = std.io.getStdOut().writer();
        var bw = std.io.bufferedWriter(stdout_file);
        const stdout = bw.writer();

        const output_file = args.output orelse {
            print("No output file given\n", .{});
            return error.NoFileGiven;
        };
        try stdout.print("writing output to {s}\n", .{output_file});
        try writeToOutputFile(allocator, output_file, output);
    } else if (std.mem.eql(u8, args.command, "sim")) {
        try sim.simulate(allocator, data);
    }
}

fn parseArgs(allocator: std.mem.Allocator) !Args {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // skip the name of this binary
    _ = args.skip();

    const command = args.next() orelse {
        print("usage: sim8086 [decode, sim] <input_file_name> <output_file_name>\nOutput file is optional.\n", .{});
        return error.NoCommandGiven;
    };

    if (!(std.mem.eql(u8, command, "decode") or std.mem.eql(u8, command, "sim"))) {
        print("Invalid command", .{});
        return error.InvalidCommand;
    }

    const arg2 = args.next() orelse return error.NoFileGiven;
    const arg3 = args.next() orelse null;

    return Args{
        .command = command,
        .input = arg2,
        .output = arg3,
    };
}

fn readInputFile(allocator: std.mem.Allocator, file_name: []const u8) ![]u8 {
    const relative_path_parts = [_][]const u8{ resource_dir, file_name };
    const relative_path = try std.mem.concat(allocator, u8, &relative_path_parts);

    const file = try std.fs.cwd().openFile(relative_path, .{});
    defer file.close();

    const fs = try file.stat();
    const data = try allocator.alloc(u8, fs.size);
    _ = try file.readAll(data);

    return data;
}

fn writeToOutputFile(allocator: std.mem.Allocator, file_name: []const u8, output: []const u8) !void {
    std.debug.assert(std.mem.containsAtLeast(u8, file_name, 1, ".asm"));

    const relative_path_parts = [_][]const u8{ output_dir, file_name };
    const relative_path = try std.mem.concat(allocator, u8, &relative_path_parts);

    const file = try std.fs.cwd().createFile(relative_path, .{
        .read = true,
        .truncate = true,
    });

    defer file.close();
    try file.writeAll(output);
}

/// adds to the outputted assembly: a comment with the name of the inputted binary file
/// and the 'bits 16' directive
fn addHeader(
    allocator: std.mem.Allocator,
    input_file_name: []const u8,
    assembly: []const u8,
) ![]const u8 {
    const header_parts = [_][]const u8{
        "; ",
        input_file_name,
        "\n",
        "bits 16\n\n",
        assembly,
    };

    const header = try std.mem.concat(allocator, u8, &header_parts);

    return header;
}

const Args = struct {
    command: []const u8,
    input: []const u8,
    output: ?[]const u8,
};

test "read sample input file" {
    const file_name = "listing_0037_single_register_mov.asm";
    const buf = try readInputFile(file_name);
    print("{s}\n", .{buf});
}

test "add header" {
    const allocator = std.testing.allocator;
    const file_name = "listing_0037_single_register_mov.asm";
    const buf =
        \\bits 16
        \\
        \\mov cx, bx
    ;

    const with_header = try addHeader(allocator, file_name, buf);
    defer allocator.free(with_header);

    print("assembly with header:\n {s}\n", .{with_header});
}

test "decode" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var data = [_]u8{ 0b1000_1001, 0b1101_1001 };

    var assembly = try decode.decode(allocator, &data);
    defer assembly.deinit();
    print("assembly: {s}\n", .{assembly.items});
    try std.testing.expect(std.mem.containsAtLeast(u8, assembly.items, 1, "mov"));
    try std.testing.expect(std.mem.containsAtLeast(u8, assembly.items, 1, "cx"));
    try std.testing.expect(std.mem.containsAtLeast(u8, assembly.items, 1, "bx"));
}
