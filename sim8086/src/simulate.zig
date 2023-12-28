const std = @import("std");
const print = @import("std").debug.print;
const decode = @import("decoding.zig");

const Instruction = struct {
    opcode: []const u8,
    dst: []const u8,
    src: []const u8,
    dst_reg_idx: usize,
    src_reg_idx: usize,
    immediate: u17,
};

// const register_labels = [_][]const u8{ "al", "cl", "dl", "bl", "ah", "ch", "dh", "bh", "ax", "cx", "dx", "bx", "sp", "bp", "si", "di" };
const register_labels = [_][]const u8{ "ax", "bx", "cx", "dx", "sp", "bp", "si", "di" };

// TODO: change to a comptime hashmap
const opcode_labels = [_][]const u8{"mov"};
const Opcode = enum(u8) { mov };

pub const State = struct {
    // registers: [16]u16,
    registers: [register_labels.len]u16,

    fn init() State {
        return State{
            // .registers = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
            .registers = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
        };
    }

    pub fn simulateInstruction(self: *State, allocator: std.mem.Allocator, assembly_line: []const u8) ![]const u8 {
        const initial_state = self.*;

        const instruction = splitAssemblyLine(assembly_line);
        const opcode = try findOpcode(instruction.opcode);
        switch (opcode) {
            Opcode.mov => mov(self, instruction),
        }
        // const new_state = funcs[opcode.funcIdx](self, instruction);

        const diff = try makeDiff(allocator, initial_state, self.*);

        return diff;
    }

    fn makeDiff(allocator: std.mem.Allocator, old_state: State, new_state: State) ![]const u8 {
        var changed_reg_idx: usize = undefined;
        var old_value: u16 = 0;
        var new_value: u16 = 0;
        for (0..register_labels.len) |i| {
            if (old_state.registers[i] != new_state.registers[i]) {
                changed_reg_idx = i;
                old_value = old_state.registers[i];
                new_value = new_state.registers[i];
            }
        }

        if (old_value == new_value) {
            return error.NoDiff;
        }

        const changed_reg = register_labels[changed_reg_idx];

        var diff_parts = try allocator.alloc([]const u8, 5);
        diff_parts[0] = " ; ";
        diff_parts[1] = changed_reg;
        diff_parts[2] = ":";
        diff_parts[3] = try std.fmt.allocPrint(allocator, "{x}->", .{old_value});
        diff_parts[4] = try std.fmt.allocPrint(allocator, "{x}", .{new_value});
        const diff = try std.mem.concat(allocator, u8, diff_parts);
        return diff;
    }

    fn printState(self: State, assembly: []const u8) void {
        print("{s}\n", .{assembly});
        print("Final registers:\n", .{});
        for (self.registers, 0..) |reg, i| {
            print("     {0s}: 0x{1x:0>4} ({1d})\n", .{ register_labels[i], reg });
        }
    }
};

pub fn simulate(allocator: std.mem.Allocator, data: []const u8) !void {
    // var state = &State{};
    var state = State.init();
    var mut_state = &state;

    var assembly = std.ArrayList(u8).init(allocator);

    var iter = decode.InstructionParser{ .buf = data };

    while (iter.next()) |instruction| {
        const line = try decode.instructionToAsm(allocator, instruction);
        const diff = try mut_state.simulateInstruction(allocator, line);
        try assembly.appendSlice(line);
        try assembly.appendSlice(diff);
        try assembly.appendSlice("\n");
    }
    mut_state.printState(assembly.items);

    // return assembly;
}

fn mov(state: *State, instruction: Instruction) void {
    if (instruction.immediate < std.math.maxInt(u17)) {
        state.registers[instruction.dst_reg_idx] = @truncate(instruction.immediate);
        return;
    }
    state.registers[instruction.dst_reg_idx] = state.registers[instruction.src_reg_idx];
}

fn splitAssemblyLine(assembly_line: []const u8) Instruction {
    // print("assembly: {s}\n", .{assembly_line});
    var instruction: Instruction = undefined;

    instruction.opcode = assembly_line[0..4];
    var args_iter = std.mem.splitScalar(u8, assembly_line[4..], ',');
    instruction.dst = std.mem.trim(u8, args_iter.next().?, " ");
    instruction.src = std.mem.trim(u8, args_iter.next().?, " ");

    for (register_labels, 0..) |reg, j| {
        if (std.mem.eql(u8, instruction.dst, reg)) {
            instruction.dst_reg_idx = j;
        }
        if (std.mem.eql(u8, instruction.src, reg)) {
            instruction.src_reg_idx = j;
        }
    }

    instruction.immediate = std.fmt.parseInt(u17, instruction.src, 10) catch std.math.maxInt(u17);

    return instruction;
}

fn findOpcode(opcode: []const u8) !Opcode {
    const clean_opcode = std.mem.trim(u8, opcode, " \n\t,");
    for (opcode_labels, 0..) |opcode_label, i| {
        if (std.mem.eql(u8, opcode_label, clean_opcode)) {
            return @enumFromInt(i);
        }
    }
    return error.InvalidOpcode;
}
