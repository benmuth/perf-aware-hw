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
    jump: i8,
};

const AssemblyInstruction = struct {
    line: []const u8,
    size: u8,
};

// probably can just roll state and simulator together in one struct
pub const Simulator = struct {
    state: *State,

    pub fn init(state: *State) !Simulator {
        return Simulator{
            .state = state,
        };
    }

    pub fn simulate(self: Simulator, allocator: std.mem.Allocator, instruction_list: []AssemblyInstruction) !void {
        var assembly_with_diff = std.ArrayList(u8).init(allocator);
        var i: usize = self.state.ip_register;
        while (i < instruction_list.len) {
            const assembly_instruction = instruction_list[i];
            if (assembly_instruction.size == 0) {
                i += 1;
                continue;
            }
            try assembly_with_diff.appendSlice(assembly_instruction.line);

            const diff = try self.state.simulateInstruction(allocator, assembly_instruction);
            try assembly_with_diff.appendSlice(diff);
            try assembly_with_diff.appendSlice("\n");

            i = self.state.ip_register;
        }
        self.state.printFinal(assembly_with_diff.items);
    }
};

pub fn getInstructions(allocator: std.mem.Allocator, machine_code: []const u8) ![]AssemblyInstruction {
    var instruction_list: []AssemblyInstruction = try allocator.alloc(AssemblyInstruction, 32);

    for (0..instruction_list.len) |i| {
        instruction_list[i] = AssemblyInstruction{ .line = "", .size = 0 };
    }

    var iter = decode.InstructionParser{ .buf = machine_code };
    var idx: usize = 0;
    while (iter.next()) |instruction| {
        const line = try decode.instructionToAsm(allocator, instruction);
        const assembly_instruction = AssemblyInstruction{ .line = line, .size = instruction.size };
        instruction_list[idx] = assembly_instruction;
        idx += assembly_instruction.size;
    }
    return instruction_list;
}

// const register_labels = [_][]const u8{ "al", "cl", "dl", "bl", "ah", "ch", "dh", "bh", "ax", "cx", "dx", "bx", "sp", "bp", "si", "di" };
const register_labels = [_][]const u8{ "ax", "bx", "cx", "dx", "sp", "bp", "si", "di" };

// TODO: change to a comptime hashmap?
const opcode_labels = [_][]const u8{ "mov", "add", "sub", "cmp", "jne" };
const Opcode = enum(u8) { mov, add, sub, cmp, jne };

pub const State = struct {
    registers: [register_labels.len]u16,

    ip_register: u16,
    zero_flag: bool,
    sign_flag: bool,

    pub fn init() State {
        return State{
            // .registers = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
            .registers = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
            .ip_register = 0,
            .zero_flag = false,
            .sign_flag = false,
        };
    }

    pub fn simulateInstruction(
        self: *State,
        allocator: std.mem.Allocator,
        assembly_instruction: AssemblyInstruction,
    ) ![]const u8 {
        const initial_state = self.*;
        self.ip_register += assembly_instruction.size;

        const instruction = try splitAssemblyLine(assembly_instruction.line);
        const opcode = try findOpcode(instruction.opcode);
        switch (opcode) {
            Opcode.mov => mov(self, instruction),
            Opcode.add => add(self, instruction),
            Opcode.sub => sub(self, instruction),
            Opcode.cmp => cmp(self, instruction),
            Opcode.jne => jne(self, instruction),
        }

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

        // ip register
        var ip_diff_parts = try allocator.alloc([]const u8, 3);
        ip_diff_parts[0] = "ip:";
        ip_diff_parts[1] = try std.fmt.allocPrint(allocator, "0x{x}->", .{old_state.ip_register});
        ip_diff_parts[2] = try std.fmt.allocPrint(allocator, "0x{x} ", .{new_state.ip_register});
        const ip_diff = try std.mem.concat(allocator, u8, ip_diff_parts);

        // flags
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
            flag_diff_parts[0] = " flags:";
            flag_diff_parts[1] = old_flag_state;
            flag_diff_parts[2] = "->";
            flag_diff_parts[3] = new_flag_state;
            flag_diff = try std.mem.concat(allocator, u8, flag_diff_parts);
        } else {
            flag_diff = "";
        }

        var diff_parts = try allocator.alloc([]const u8, 6);
        diff_parts[0] = " ; ";
        diff_parts[1] = reg_diff;
        diff_parts[2] = " ";
        diff_parts[3] = ip_diff;
        diff_parts[4] = " ";
        diff_parts[5] = flag_diff;
        const diff = try std.mem.concat(allocator, u8, diff_parts);
        return diff;
    }

    fn printState(self: State) void {
        print("\n", .{});
        for (self.registers, 0..) |reg, i| {
            print("     {0s}: 0x{1x:0>4} ({1d})\n", .{ register_labels[i], reg });
        }
        print("     ip: 0x{0x:0>4} ({0d})\n", .{self.ip_register});
        print("   flags: Z({}) S({})\n", .{ self.zero_flag, self.sign_flag });
    }

    fn printFinal(self: State, assembly: []const u8) void {
        print("print state ptr: {*}\n", .{&self});

        print("{s}\n", .{assembly});
        print("Final registers:\n", .{});
        for (self.registers, 0..) |reg, i| {
            if (reg > 0) {
                print("     {0s}:0x{1x:0>4} ({1d})\n", .{ register_labels[i], reg });
            }
        }
        print("     ip: 0x{0x:0>4} ({0d})\n", .{self.ip_register});
        print("   flags: Z({}) S({})\n", .{ self.zero_flag, self.sign_flag });
    }
};

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

fn jne(state: *State, instruction: Instruction) void {
    if (!state.zero_flag) {
        const ip_value = state.ip_register;
        const jump_value = instruction.jump;

        const wide_jump = @as(i16, jump_value);
        const signed_ip_value: i16 = @bitCast(ip_value);

        const final_ip_reg: u16 = @bitCast(signed_ip_value + wide_jump);
        state.ip_register = final_ip_reg;
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
    const result, _ = @addWithOverflow(term1, term2);
    return result;
}

fn splitAssemblyLine(assembly_line: []const u8) !Instruction {
    var instruction: Instruction = undefined;

    instruction.opcode = assembly_line[0..3];
    print("opcode: {s}\n", .{instruction.opcode});
    if (std.mem.eql(u8, instruction.opcode, "jne")) {
        var args_iter = std.mem.splitScalar(u8, assembly_line[4..], ' ');
        const immediate_str = std.mem.trim(u8, args_iter.next().?, " ");
        const immediate = try std.fmt.parseInt(i8, immediate_str, 10);
        instruction.jump = immediate;
        return instruction;
    }

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

test "concat" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const concat_parts = try allocator.alloc([]const u8, 2);
    concat_parts[0] = "foo";
    concat_parts[1] = "";
    const concat = try std.mem.concat(allocator, u8, concat_parts);
    print("concat: {s}\n", .{concat});
}
