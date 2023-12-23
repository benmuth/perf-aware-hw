const std = @import("std");
const print = @import("std").debug.print;
const code = @import("encoding.zig");

const resource_dir = "/Users/ben/Documents/Programming/perf-aware/resources/part1";

pub fn main() !void {
    var fileNames = getFileNames() catch {
        print("failed to get file name", .{});
        return;
    };

    var inputFile = openFile(fileNames.input) catch {
        print("failed to open input file with file name {s}", .{fileNames.input});
        return;
    };
    defer inputFile.close();

    const fs = try inputFile.stat();

    // print("{d}\n", .{fs.size});

    const size = 1000;

    var buf: [size]u8 = undefined;
    _ = try inputFile.read(&buf);

    var data = buf[0..fs.size];

    var assembly = code.decode(data);

    var outputFile = openFile(fileNames.output) catch {
        print("failed to open output file with file name {s}", .{fileNames.output});
        return;
    };
    defer outputFile.close();
    outputFile.writeAll(assembly);
}

fn getFileNames() FileError!type {
    var args = std.process.args();

    // skip the name of this binary
    _ = args.skip();
    var inputFileName = args.next();
    if (!inputFileName) { // payload capture
        return FileError.NoFileGiven;
    }

    var outputFileName = args.next();
    if (!outputFileName) {
        return FileError.NoFileGiven;
    }
    var files = struct {
        input: []const u8,
        output: []const u8,
    };
    files.input = inputFileName;
    files.output = outputFileName;
    return files;
}

const FileError = error{NoFileGiven};

fn openFile(fileName: []const u8) !std.fs.File {
    var dir = std.fs.openDirAbsolute(resource_dir, .{ .access_sub_paths = true }) catch |err| {
        print("failed to open dir", .{});
        return err;
    };

    defer dir.close();

    const file = dir.openFile(fileName, .{}) catch |err| {
        print("failed to open file in resource dir\n", .{});
        return err;
    };
    return file;
}

fn writeOutput(file: std.fs.File, output: []const u8) !void {
    var disasm = "bits 16\n" ++ output;
    var n = try file.writeAll(disasm);
    print("{} bytes written\n", .{n});
}
