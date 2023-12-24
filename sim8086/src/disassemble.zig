const std = @import("std");
const print = @import("std").debug.print;
const code = @import("encoding.zig");

const resource_dir = "/home/ben/code/perf-aware/resources/part1/";
const output_dir = "/home/ben/code/perf-aware/hw/sim8086/output";

// const FileError = error{ NoFileGiven, FileNotFound };

// example usage for this program:
// zig-out/bin/sim8086 listing_0037_single_register_mov listing_0037_single_register_mov.asm

// given the name of a machine code file as input, and the name of an output file, disassembles the input file and writes the assembly to the output file

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var allocator = arena.allocator();

    var file_names = try getFileNames(allocator);
    const data = try readInputFile(file_names.input);

    var assembly = try code.decode(allocator, data);

    const output = try addHeader(allocator, file_names.input, assembly);

    print("writing output to {s}\n", .{file_names.output});
    try writeOutput(file_names.output, output);
}

fn getFileNames(allocator: std.mem.Allocator) !IOFiles {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // skip the name of this binary
    _ = args.skip();
    var input_file_name = args.next() orelse return error.NoFileGiven;

    var output_file_name = args.next() orelse return error.NoFileGiven;
    return IOFiles{
        .input = input_file_name,
        .output = output_file_name,
    };
}

fn openFile(file_name: []const u8, dir_name: []const u8) !std.fs.File {
    var dir = try std.fs.openDirAbsolute(dir_name, .{ .access_sub_paths = true });

    defer dir.close();

    const file = dir.createFile(file_name, .{ .mode = 0o600, .read = true, .truncate = false });
    return file;
}

fn readInputFile(file_name: []const u8) ![]u8 {
    var input_file = try openFile(file_name, resource_dir);
    defer input_file.close();

    const fs = try input_file.stat();

    var arr: [4096]u8 = undefined;
    var buf = arr[0..fs.size];
    _ = try input_file.readAll(buf);

    return buf;
}

fn writeOutput(file_name: []const u8, output: []const u8) !void {
    std.debug.assert(std.mem.containsAtLeast(u8, file_name, 1, ".asm"));
    var output_file = try openFile(file_name, output_dir);
    defer output_file.close();
    try output_file.writeAll(output);
}

/// adds to the outputted assembly: a comment with the name of the inputted binary file, and the 'bits 16' directive
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

const IOFiles = struct {
    input: []const u8,
    output: []const u8,
};

test "decode" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    // const input_file = "listing_0037_single_register_mov";
    // const data = try readInputFile(input_file);
    // print("data: {b}\n", .{data});

    var data = [_]u8{ 0b1000_1001, 0b1101_1001 };

    var assembly = try code.decode(allocator, &data);
    defer assembly.deinit();
    print("assembly: {s}\n", .{assembly.items});
    try std.testing.expect(std.mem.containsAtLeast(u8, assembly.items, 1, "mov"));
    try std.testing.expect(std.mem.containsAtLeast(u8, assembly.items, 1, "cx"));
    try std.testing.expect(std.mem.containsAtLeast(u8, assembly.items, 1, "bx"));
}
