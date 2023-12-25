const std = @import("std");
const print = std.debug.print;

const AssemblyIterator = struct {
    buf: []u8,
    index: usize = 0,

    fn next(self: *AssemblyIterator) ?Instruction {
        print("NEXT\n", .{});
        const index = self.index;

        // for (index..self.buf.len) |i| {
        const buf_end = if (index + 7 < self.buf.len) index + 7 else self.buf.len;
        // print("buf end: {d}\n", .{buf_end});
        // print("slice: {any}\n", .{self.buf[index..buf_end]});

        // print("BEFORE\n", .{});
        // for (22..29) |i| {
        //     print("{x} ", .{self.buf[i]});
        // }
        // print("\n", .{});

        const parsed_instruction = parseInstruction(self.buf[index..buf_end]) catch return null;
        // print("AFTER\n", .{});
        // for (22..29) |i| {
        //     print("{x} ", .{self.buf[i]});
        // }
        // print("\n", .{});
        self.index += parsed_instruction.size;
        return parsed_instruction;
        // }
    }
};

pub fn decode(allocator: std.mem.Allocator, data: []u8) !std.ArrayList(u8) {
    print("buf: {}\n", .{std.fmt.fmtSliceHexLower(data)});
    var assembly = std.ArrayList(u8).init(allocator);

    var iter = AssemblyIterator{ .buf = data };

    // for (22..29) |i| {
    //     print("byte: {b}\n", .{buf[i]});
    // }
    // print("22 to 29: {b}\n", .{buf[22..29]});

    while (iter.next()) |instruction| {
        // print("buf: {}\n", .{std.fmt.fmtSliceHexLower(buf)});
        print("BEFORE\n", .{});
        for (22..29) |i| {
            print("{x} ", .{iter.buf[i]});
        }
        print("\n", .{});
        print("instruction: {any}\n", .{instruction});
        var line = try binToAsm(allocator, instruction);
        print("AFTER\n", .{});
        for (22..29) |i| {
            print("{x} ", .{iter.buf[i]});
        }
        print("\n", .{});
        try assembly.appendSlice(line);
    } else {
        print("iter index: {d}\n", .{iter.index});
        print("buf size : {d}\n", .{iter.buf.len});
    }
    print("assembly: {s}\n", .{assembly.items});
    return assembly;
}

pub fn parseInstruction(bytes: []u8) !Instruction {
    // print("bytes: {x}\n", .{std.fmt.fmtSliceHexLower(bytes)});
    var parsed_instruction: Instruction = undefined;

    parsed_instruction.opcode = try parseOpcode(bytes[0]);
    switch (parsed_instruction.opcode) {
        opcode_encoding.normal_mov => {
            // print("bytes: {b} {b}\n", .{ bytes[0], bytes[1] });
            parsed_instruction.d = (bytes[0] & 0b00000010) >> 1;
            parsed_instruction.w = (bytes[0] & 0b00000001) >> 0;
            parsed_instruction.mod = (bytes[1] & 0b11000000) >> 6;
            parsed_instruction.reg = (bytes[1] & 0b00111000) >> 3;
            parsed_instruction.rm = (bytes[1] & 0b00000111) >> 0;
            switch (parsed_instruction.mod) {
                0b00 => {
                    if (parsed_instruction.rm == 0b110) {
                        parsed_instruction.size = 4;
                        const hi = @shlExact(@as(u16, bytes[3]), 8);
                        parsed_instruction.data = hi | @as(u16, bytes[2]);
                    } else {
                        parsed_instruction.size = 2;
                    }
                },
                0b11 => parsed_instruction.size = 2,
                0b01 => {
                    parsed_instruction.size = 3;
                    parsed_instruction.data = bytes[2];
                },
                0b10 => {
                    parsed_instruction.size = 4;
                    const hi = @shlExact(@as(u16, bytes[3]), 8);
                    parsed_instruction.data = hi | @as(u16, bytes[2]);
                },
                else => unreachable,
            }

            // const ea_calc = effective_address_calculation[parsed_instruction.rm];
            // parsed_instruction.ea_calc = ea_calc;
        },
        opcode_encoding.imm_to_reg => {
            parsed_instruction.w = (bytes[0] & 0b00001000) >> 3;
            parsed_instruction.reg = (bytes[0] & 0b00000111) >> 0;
            if (parsed_instruction.w == 0) {
                parsed_instruction.size = 2;
                parsed_instruction.data = bytes[1];
            } else {
                parsed_instruction.size = 3;
                // parsed_instruction.data = bytes[1] << 8 | bytes[2];
                const hi = @shlExact(@as(u16, bytes[2]), 8);
                parsed_instruction.data = hi | @as(u16, bytes[1]);
                // print("long data: {b:0>8} {b:0>8}\n", .{ hi, bytes[2] });
                // print("hi: {0b}\n", .{hi >> 8});
                // print("parsed data: {b:0>16}\n", .{parsed_instruction.data});
                // print("parsed data: {d}\n", .{parsed_instruction.data});
            }
        },
    }
    // print("parsed instruction: {any}\n", .{parsed_instruction});
    return parsed_instruction;
}

fn parseOpcode(byte: u8) !opcode_encoding {
    if (((byte & 0b11110000) ^ 0b10110000) == 0) {
        return opcode_encoding.imm_to_reg;
    }
    if (((byte & 0b11111100) ^ 0b10001000) == 0) {
        return opcode_encoding.normal_mov;
    }
    return error.FailedToParse;
}

fn calcAddress(allocator: std.mem.Allocator, instruction: Instruction) ![]const u8 {
    // if (instruction.rm == 0b110) {
    //     return try std.fmt.allocPrint(allocator, "{d}", .{instruction.data});
    // }
    const formula = effective_address_calculation[instruction.rm];
    var formula_parts: [][]const u8 = undefined;
    switch (instruction.mod) {
        0b00 => {
            if (instruction.rm == 0b110) { // direct address
                formula_parts = try allocator.alloc([]const u8, 3);
                formula_parts[0] = "[";
                formula_parts[1] = try std.fmt.allocPrint(allocator, "{d}", .{instruction.data});
                formula_parts[2] = "]";
            } else {
                formula_parts = try allocator.alloc([]const u8, 3);
                formula_parts[0] = "[";
                formula_parts[1] = formula;
                formula_parts[2] = "]";
            }
        },
        0b01, 0b10 => {
            formula_parts = try allocator.alloc([]const u8, 5);
            formula_parts[0] = "[";
            formula_parts[1] = formula;
            formula_parts[2] = "+";
            formula_parts[3] = try std.fmt.allocPrint(allocator, "{d}", .{instruction.data});
            formula_parts[4] = "]";
        },
        else => unreachable,
    }

    const formula_str = try std.mem.concat(allocator, u8, formula_parts);
    return formula_str;
}

/// returns a line of assembly translated from a parsed instruction
fn binToAsm(allocator: std.mem.Allocator, instruction: Instruction) ![]const u8 {
    // var dst: u8 = undefined;
    // var src: u8 = undefined;

    var dst_str: []const u8 = undefined;
    var src_str: []const u8 = undefined;

    var formula: []const u8 = undefined;
    if (instruction.opcode == opcode_encoding.normal_mov) {
        if (instruction.mod != 0b11) {
            formula = try calcAddress(allocator, instruction);
        }
        if (instruction.d == 0) {
            src_str = registers[instruction.reg][instruction.w];
            if (instruction.mod == 0b11) {
                dst_str = registers[instruction.rm][instruction.w];
            } else {
                dst_str = try calcAddress(allocator, instruction);
            }
        } else {
            if (instruction.mod == 0b11) {
                src_str = registers[instruction.rm][instruction.w];
            } else {
                src_str = try calcAddress(allocator, instruction);
            }
            dst_str = registers[instruction.reg][instruction.w];
        }
    } else if (instruction.opcode == opcode_encoding.imm_to_reg) {
        // dst = instruction.reg;
        dst_str = registers[instruction.reg][instruction.w];
    }

    // dst_str = registers[dst][instruction.w];
    // src_str = registers[src][instruction.w];
    var opcode: []const u8 = undefined;
    switch (instruction.opcode) {
        opcode_encoding.normal_mov,
        opcode_encoding.imm_to_reg,
        => opcode = "mov",
    }

    var instruction_parts: [][]const u8 = undefined;
    // put parts together
    switch (instruction.opcode) {
        opcode_encoding.normal_mov => {
            instruction_parts = try allocator.alloc([]const u8, 6);
            instruction_parts[0] = opcode;
            instruction_parts[1] = " ";
            instruction_parts[2] = dst_str;
            instruction_parts[3] = ", ";
            instruction_parts[4] = src_str;
            instruction_parts[5] = "\n";
        },
        opcode_encoding.imm_to_reg => {
            instruction_parts = try allocator.alloc([]const u8, 6);
            instruction_parts[0] = opcode;
            instruction_parts[1] = " ";
            instruction_parts[2] = dst_str;
            instruction_parts[3] = ", ";
            instruction_parts[4] = try std.fmt.allocPrint(allocator, "{d}", .{instruction.data});
            instruction_parts[5] = "\n";
        },
    }

    const instruction_str = try std.mem.concat(allocator, u8, instruction_parts);
    return instruction_str;
}

const registers = [8][2][]const u8{
    .{ "al", "ax" },
    .{ "cl", "cx" },
    .{ "dl", "dx" },
    .{ "bl", "bx" },
    .{ "ah", "sp" },
    .{ "ch", "bp" },
    .{ "dh", "si" },
    .{ "bh", "di" },
};

// holds the values of each field of an instruction
const Instruction = struct {
    // which instruction to execute, like MOV
    // 6 bits
    opcode: opcode_encoding,

    // "direction": does the 'reg' field define the src or dst?
    // 1 bit
    d: u8,

    // "word": operating on 8-bit (byte) data or 16-bit (word) data
    // 1 bit
    w: u8,

    // "mode": reg to memory, or register to register?
    // 2 bits
    mod: u8,

    // "register": identifies a register to store to or load from
    // 3 bits
    reg: u8,

    // "register/memory": depending on 'mod' field, helps with either the second
    // register or memory address
    // 3 bits
    rm: u8,

    data: u16,

    // the size this instruction took to encode, in bytes
    size: u8,

    pub fn printMe(self: *Instruction) void {
        const fields = std.meta.fields(@TypeOf(self.*));
        inline for (fields) |field| {
            print("{s}: {b} ", .{ field.name, @field(self.*, field.name) });
        }
        print("\n", .{});
    }
};

// TODO: expand to more opcodes
// NOTE: should be a map?
const opcode_encoding = enum(u8) {
    normal_mov = 0b100010,
    imm_to_reg = 0b1011,
};

// const register_enum = enum {
//     AL,
//     CL,
//     DL,
//     BL,
//     AH,
//     CH,
//     DH,
//     BH,
//     AX,
//     CX,
//     DX,
//     BX,
//     SP,
//     BP,
//     SI,
//     DI,
// };

const effective_address_calculation = [_][]const u8{
    "bx + si",
    "bx + di",
    "bp + si",
    "bp + di",
    "si",
    "di",
    "dir_add",
    "bx",
};

const mod = enum(u2) {
    mem,
    mem_8,
    mem_16,
    reg,
};

// test ""
