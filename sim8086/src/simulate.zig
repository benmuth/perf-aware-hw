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
const opcode_labels = [_][]const u8{ "mov", "add", "sub", "cmp" };
const Opcode = enum(u8) { mov, add, sub, cmp };

pub const State = struct {
    // registers: [16]u16,
    registers: [register_labels.len]u16,

    ip_register: u16,
    // parity_flag: bool,
    zero_flag: bool,
    sign_flag: bool,

    fn init() State {
        return State{
            // .registers = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
            .registers = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
            .ip_register = 0,
            // .parity_flag = false,
            .zero_flag = false,
            .sign_flag = false,
        };
    }

    pub fn simulateInstruction(self: *State, allocator: std.mem.Allocator, assembly_line: []const u8) ![]const u8 {
        const initial_state = self.*;

        const instruction = splitAssemblyLine(assembly_line);
        const opcode = try findOpcode(instruction.opcode);
        switch (opcode) {
            Opcode.mov => mov(self, instruction),
            Opcode.add => add(self, instruction),
            Opcode.sub => sub(self, instruction),
            Opcode.cmp => cmp(self, instruction),
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

        var reg_diff_parts = try allocator.alloc([]const u8, 4);
        var reg_diff: []const u8 = undefined;

        if (old_value != new_value) {
            reg_diff_parts[0] = register_labels[changed_reg_idx];
            reg_diff_parts[1] = ":";
            reg_diff_parts[2] = try std.fmt.allocPrint(allocator, "0x{x}->", .{old_value});
            reg_diff_parts[3] = try std.fmt.allocPrint(allocator, "0x{x}", .{new_value});
            reg_diff = try std.mem.concat(allocator, u8, reg_diff_parts);
        } else {
            reg_diff = "";
        }

        var old_flag_state: []const u8 = undefined;
        if (old_state.zero_flag) {
            old_flag_state = "Z";
        } else if (old_state.sign_flag) {
            old_flag_state = "S";
        } else {
            old_flag_state = "";
        }

        var new_flag_state: []const u8 = undefined;
        if (new_state.zero_flag) {
            new_flag_state = "Z";
        } else if (new_state.sign_flag) {
            new_flag_state = "S";
        } else {
            new_flag_state = "";
        }

        const flag_changed = old_state.zero_flag != new_state.zero_flag or old_state.sign_flag != new_state.sign_flag;

        var flag_diff_parts = try allocator.alloc([]const u8, 4);
        var flag_diff: []const u8 = undefined;
        if (flag_changed) {
            // print("yes flag diff\n", .{});
            flag_diff_parts[0] = " flags:";
            flag_diff_parts[1] = old_flag_state;
            flag_diff_parts[2] = "->";
            flag_diff_parts[3] = new_flag_state;
            flag_diff = try std.mem.concat(allocator, u8, flag_diff_parts);
        } else {
            // print("no flag diff\n", .{});
            flag_diff = "";
        }

        var diff_parts = try allocator.alloc([]const u8, 4);
        diff_parts[0] = " ; ";
        diff_parts[1] = reg_diff;
        diff_parts[2] = " ";
        diff_parts[3] = flag_diff;
        // diff_parts[4] = try std.fmt.allocPrint(allocator, "{x}", .{new_value});
        // diff_parts[5] =
        // print("flag diff len: {d}\n", .{flag_diff.len});
        // print("reg diff len: {d}\n", .{reg_diff.len});
        // print("diff parts len: {d}\n", .{diff_parts.len});
        const diff = try std.mem.concat(allocator, u8, diff_parts);
        return diff;
    }

    fn printState(self: State) void {
        print("\n", .{});
        for (self.registers, 0..) |reg, i| {
            print("     {0s}: 0x{1x:0>4} ({1d})\n", .{ register_labels[i], reg });
        }
        print("   flags: Z({}) S({})\n", .{ self.zero_flag, self.sign_flag });
    }

    fn printFinal(self: State, assembly: []const u8) void {
        print("{s}\n", .{assembly});
        print("Final registers:\n", .{});
        for (self.registers, 0..) |reg, i| {
            if (reg > 0) {
                print("     {0s}:0x{1x:0>4} ({1d})\n", .{ register_labels[i], reg });
            }
        }
        print("   flags: Z({}) S({})\n", .{ self.zero_flag, self.sign_flag });
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
    mut_state.printFinal(assembly.items);

    // return assembly;
}

fn mov(state: *State, instruction: Instruction) void {
    var src_value: u16 = 0;
    if (instruction.immediate < std.math.maxInt(u17)) {
        src_value = @truncate(instruction.immediate);
    } else {
        src_value = state.registers[instruction.src_reg_idx];
    }
    state.registers[instruction.dst_reg_idx] = src_value;
}

fn add(state: *State, instruction: Instruction) void {
    var src_value: u16 = 0;
    if (instruction.immediate < std.math.maxInt(u17)) {
        src_value = @truncate(instruction.immediate);
    } else {
        src_value = state.registers[instruction.src_reg_idx];
    }
    const dst_value = arithAdd(state.registers[instruction.dst_reg_idx], src_value);
    state.registers[instruction.dst_reg_idx] = dst_value;

    if (dst_value & 0x8000 > 0) {
        state.sign_flag = true;
    } else {
        state.sign_flag = false;
    }
    if (dst_value == 0) {
        state.zero_flag = true;
    } else {
        state.zero_flag = false;
    }
}

fn sub(state: *State, instruction: Instruction) void {
    var src_value: u16 = 0;
    if (instruction.immediate < std.math.maxInt(u17)) {
        src_value = @truncate(instruction.immediate);
    } else {
        src_value = state.registers[instruction.src_reg_idx];
    }
    const dst_value = arithSubtract(state.registers[instruction.dst_reg_idx], src_value);
    state.registers[instruction.dst_reg_idx] = dst_value;

    if (dst_value & 0x8000 > 0) {
        state.sign_flag = true;
    } else {
        state.sign_flag = false;
    }
    if (dst_value == 0) {
        state.zero_flag = true;
    } else {
        state.zero_flag = false;
    }
}

fn cmp(state: *State, instruction: Instruction) void {
    var src_value: u16 = 0;
    if (instruction.immediate < std.math.maxInt(u17)) {
        src_value = @truncate(instruction.immediate);
    } else {
        src_value = state.registers[instruction.src_reg_idx];
    }
    const cmp_value = arithSubtract(state.registers[instruction.dst_reg_idx], src_value);
    // state.registers[instruction.dst_reg_idx] = dst_value;

    if (cmp_value & 0x8000 > 0) {
        state.sign_flag = true;
    } else {
        state.sign_flag = false;
    }
    if (cmp_value == 0) {
        state.zero_flag = true;
    } else {
        state.zero_flag = false;
    }
}

fn arithSubtract(term1: u16, term2: u16) u16 {
    var ret: u16 = undefined;
    if (term2 > term1) {
        ret = std.math.maxInt(u16) - (term2 - term1);
    } else {
        ret = term1 - term2;
    }
    return ret;
}

fn arithAdd(term1: u16, term2: u16) u16 {
    // var ret: u16 = undefined;
    // const result, _ = @addWithOverflow(term1, term2);
    // if (term1 + term2 > std.math.maxInt(u16)) {
    //     ret = std.math.maxInt(u16) - (term2 - term1);
    // } else {
    //     ret = term1 - term2;
    // }
    const result, _ = @addWithOverflow(term1, term2);
    return result;
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
    // print("clean opcode: {s}\n", .{clean_opcode});
    for (opcode_labels, 0..) |opcode_label, i| {
        if (std.mem.eql(u8, opcode_label, clean_opcode)) {
            return @enumFromInt(i);
        }
    }
    return error.InvalidOpcode;
}

test "sim sub instruction" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var state = State.init();

    state.registers[1] = 61443;
    state.registers[2] = 3841;
    state.printState();
    const assembly = "sub bx, cx";
    const diff = try state.simulateInstruction(allocator, assembly);
    state.printState();
    print("sub diff: .{s}\n", .{diff});
}

test "add with overflow" {
    const a: u4 = 12;
    const b: u4 = 15;
    const res, const overflow = @addWithOverflow(a, b);
    print("res: {d}, overflow: {d}\n", .{ res, overflow });
}
