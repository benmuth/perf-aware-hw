const std = @import("std");
const print = @import("std").debug.print;
const code = @import("encoding.zig");

const resource_dir = "../../../perf-aware/resources/part1/";
const output_dir = "../../../perf-aware/hw/sim8086/output/";

// example usage for this program:
// zig-out/bin/sim8086 listing_0037_single_register_mov listing_0037_single_register_mov.asm

// given the name of a binary executable file as input, and the name of an output file to write to, disassembles the input file and writes the assembly to the output file

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file_names = try getFileNames(allocator);
    const data = try readInputFile(allocator, file_names.input);

    var assembly = try code.decode(allocator, data);
    defer assembly.deinit();

    const output = try addHeader(allocator, file_names.input, assembly.items);

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("writing output to {s}\n", .{file_names.output});
    try writeToOutputFile(allocator, file_names.output, output);
}

fn getFileNames(allocator: std.mem.Allocator) !IOFiles {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // skip the name of this binary
    _ = args.skip();
    const input_file_name = args.next() orelse return error.NoFileGiven;

    const output_file_name = args.next() orelse return error.NoFileGiven;
    return IOFiles{
        .input = input_file_name,
        .output = output_file_name,
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

const IOFiles = struct {
    input: []const u8,
    output: []const u8,
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

    var assembly = try code.decode(allocator, &data);
    defer assembly.deinit();
    print("assembly: {s}\n", .{assembly.items});
    try std.testing.expect(std.mem.containsAtLeast(u8, assembly.items, 1, "mov"));
    try std.testing.expect(std.mem.containsAtLeast(u8, assembly.items, 1, "cx"));
    try std.testing.expect(std.mem.containsAtLeast(u8, assembly.items, 1, "bx"));
}
