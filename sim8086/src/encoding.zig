const std = @import("std");
const print = std.debug.print;

const AssemblyIterator = struct {
    buf: []const u8,
    index: usize = 0,

    fn next(self: *AssemblyIterator) ?Instruction {
        const index = self.index;
        const buf_end = if (index + 7 < self.buf.len) index + 7 else self.buf.len;

        const parsed_instruction = parseInstruction(self.buf[index..buf_end]) catch return null;
        self.index += parsed_instruction.size;
        return parsed_instruction;
        // }
    }
};

pub fn decode(allocator: std.mem.Allocator, data: []const u8) !std.ArrayList(u8) {
    var assembly = std.ArrayList(u8).init(allocator);

    var iter = AssemblyIterator{ .buf = data };

    while (iter.next()) |instruction| {
        const line = try binToAsm(allocator, instruction);
        print("line: {s}\n", .{line});
        try assembly.appendSlice(line);
    }
    return assembly;
}

pub fn parseInstruction(bytes: []const u8) !Instruction {
    if (bytes.len == 0) return error.NoData;

    var parsed_instruction: Instruction = undefined;
    parsed_instruction.opcode = try parseOpcode(bytes[0]);
    switch (parsed_instruction.opcode) {
        opcode_encoding.mov_normal, opcode_encoding.add_normal, opcode_encoding.sub_normal, opcode_encoding.cmp_normal => {
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
                        parsed_instruction.disp = hi | @as(u16, bytes[2]);
                    } else {
                        parsed_instruction.size = 2;
                    }
                },
                0b11 => parsed_instruction.size = 2,
                0b01 => {
                    parsed_instruction.size = 3;
                    parsed_instruction.disp = bytes[2];
                },
                0b10 => {
                    parsed_instruction.size = 4;
                    const hi = @shlExact(@as(u16, bytes[3]), 8);
                    parsed_instruction.disp = hi | @as(u16, bytes[2]);
                },
                else => unreachable,
            }
        },
        opcode_encoding.mov_imm_to_reg => {
            parsed_instruction.w = (bytes[0] & 0b00001000) >> 3;
            parsed_instruction.reg = (bytes[0] & 0b00000111) >> 0;
            if (parsed_instruction.w == 0) {
                parsed_instruction.size = 2;
                parsed_instruction.data = bytes[1];
            } else {
                parsed_instruction.size = 3;
                const hi = @shlExact(@as(u16, bytes[2]), 8);
                parsed_instruction.data = hi | @as(u16, bytes[1]);
            }
        },
        opcode_encoding.imm_to_from_with => {
            parsed_instruction.s = (bytes[0] & 0b0000_0010) >> 1;
            parsed_instruction.w = (bytes[0] & 0b0000_0001) >> 0;
            parsed_instruction.mod = (bytes[1] & 0b1100_0000) >> 6;
            parsed_instruction.opc_ext = (bytes[1] & 0b0011_1000) >> 3;
            parsed_instruction.rm = (bytes[1] & 0b0000_0111) >> 0;

            var size: u8 = 2;
            switch (parsed_instruction.mod) {
                0b00 => {},
                0b01 => {
                    parsed_instruction.disp = bytes[size];
                    size += 1;
                },
                0b10 => {
                    const hi = @shlExact(@as(u16, bytes[size + 1]), 8);
                    parsed_instruction.disp = hi | @as(u16, bytes[size]);
                    size += 2;
                },
                0b11 => {},
                else => return error.FailedToParse,
            }

            if (parsed_instruction.s == 0 and parsed_instruction.w == 1) {
                const hi_data = @shlExact(@as(u16, bytes[size + 1]), 8);
                parsed_instruction.data = hi_data | @as(u16, bytes[size]);
                size += 2;
            } else {
                parsed_instruction.data = bytes[size];
            }
            parsed_instruction.size = size;
            // switch (octal) {
            //     0b000 => parsed_instruction.octal = 0b000,
            //     0b101 => parsed_instruction.octal =
            // }
        },
        opcode_encoding.add_imm_to_acc,
        opcode_encoding.sub_imm_from_acc,
        opcode_encoding.cmp_imm_with_acc,
        => {
            parsed_instruction.w = (bytes[0] & 0b0000_0001);
            if (parsed_instruction.w == 0) {
                parsed_instruction.size = 2;
                parsed_instruction.data = bytes[1];
            } else {
                parsed_instruction.size = 3;
                const hi = @shlExact(@as(u16, bytes[2]), 8);
                parsed_instruction.data = hi | @as(u16, bytes[1]);
            }
        },
    }
    return parsed_instruction;
}

fn parseOpcode(byte: u8) !opcode_encoding {
    // add, sub, or cmp, look at second byte to know
    if (((byte & 0b1111_1100) ^ 0b1000_0000) == 0) {
        return opcode_encoding.imm_to_from_with;
    }

    if (((byte & 0b1111_0000) ^ 0b1011_0000) == 0) {
        return opcode_encoding.mov_imm_to_reg;
    }
    if (((byte & 0b1111_1100) ^ 0b1000_1000) == 0) {
        return opcode_encoding.mov_normal;
    }

    if (((byte & 0b1111_1100) ^ 0b0000_0000) == 0) {
        return opcode_encoding.add_normal;
    }
    if (((byte & 0b1111_1110) ^ 0b0000_0100) == 0) {
        return opcode_encoding.add_imm_to_acc;
    }

    if (((byte & 0b1111_1100) ^ 0b0010_1000) == 0) {
        return opcode_encoding.sub_normal;
    }
    if (((byte & 0b1111_1110) ^ 0b0010_1100) == 0) {
        return opcode_encoding.sub_imm_from_acc;
    }

    if (((byte & 0b1111_1100) ^ 0b0001_1100) == 0) {
        return opcode_encoding.cmp_normal;
    }
    if (((byte & 0b1111_1110) ^ 0b0011_1100) == 0) {
        return opcode_encoding.cmp_imm_with_acc;
    }

    return error.FailedToParse;
}

fn calcAddress(allocator: std.mem.Allocator, instruction: Instruction) ![]const u8 {
    var formula = effective_address_calculation[instruction.rm];
    if (instruction.rm == 0b110) {
        formula = registers[0b101][1];
    }
    var formula_parts: [][]const u8 = undefined;
    switch (instruction.mod) {
        0b00 => {
            if (instruction.rm == 0b110) { // direct address
                formula_parts = try allocator.alloc([]const u8, 3);
                formula_parts[0] = "[";
                formula_parts[1] = try std.fmt.allocPrint(allocator, "{d}", .{instruction.disp});
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
            formula_parts[3] = try std.fmt.allocPrint(allocator, "{d}", .{instruction.disp});
            formula_parts[4] = "]";
        },
        0b11 => {
            formula_parts = try allocator.alloc([]const u8, 1);
            formula_parts[0] = formula;
        },
        else => unreachable,
    }

    const formula_str = try std.mem.concat(allocator, u8, formula_parts);
    return formula_str;
}

/// returns a line of assembly translated from a parsed instruction
fn binToAsm(allocator: std.mem.Allocator, instruction: Instruction) ![]const u8 {
    var dst_str: []const u8 = undefined;
    var src_str: []const u8 = undefined;

    var formula: []const u8 = undefined;
    print("opcode: {any}\n", .{instruction.opcode});
    switch (instruction.opcode) {
        opcode_encoding.mov_normal,
        opcode_encoding.add_normal,
        opcode_encoding.sub_normal,
        opcode_encoding.cmp_normal,
        => {
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
        },

        opcode_encoding.mov_imm_to_reg => {
            dst_str = registers[instruction.reg][instruction.w];
        },

        opcode_encoding.imm_to_from_with => {
            dst_str = try calcAddress(allocator, instruction);
        },

        opcode_encoding.add_imm_to_acc,
        opcode_encoding.sub_imm_from_acc,
        opcode_encoding.cmp_imm_with_acc,
        => {},
        // else => return error.UnhandledOpcode,
    }

    var opcode: []const u8 = undefined;
    switch (instruction.opcode) {
        opcode_encoding.mov_normal,
        opcode_encoding.mov_imm_to_reg,
        => opcode = "mov",

        opcode_encoding.add_normal,
        opcode_encoding.add_imm_to_acc,
        => opcode = "add",

        opcode_encoding.sub_normal,
        opcode_encoding.sub_imm_from_acc,
        => opcode = "sub",

        opcode_encoding.cmp_normal,
        opcode_encoding.cmp_imm_with_acc,
        => opcode = "cmp",

        opcode_encoding.imm_to_from_with => {
            switch (instruction.opc_ext) {
                0b000 => opcode = "add",
                0b101 => opcode = "sub",
                0b111 => opcode = "cmp",
                else => return error.UnhandledOpcode,
            }
        },
    }

    var instruction_parts: [][]const u8 = undefined;
    // put parts together
    switch (instruction.opcode) {
        opcode_encoding.mov_normal,
        opcode_encoding.add_normal,
        opcode_encoding.sub_normal,
        opcode_encoding.cmp_normal,
        => {
            instruction_parts = try allocator.alloc([]const u8, 6);
            instruction_parts[0] = opcode;
            instruction_parts[1] = " ";
            instruction_parts[2] = dst_str;
            instruction_parts[3] = ", ";
            instruction_parts[4] = src_str;
            instruction_parts[5] = "\n";
        },
        opcode_encoding.mov_imm_to_reg => {
            instruction_parts = try allocator.alloc([]const u8, 6);
            instruction_parts[0] = opcode;
            instruction_parts[1] = " ";
            instruction_parts[2] = dst_str;
            instruction_parts[3] = ", ";
            instruction_parts[4] = try std.fmt.allocPrint(allocator, "{d}", .{instruction.data});
            instruction_parts[5] = "\n";
        },
        opcode_encoding.add_imm_to_acc,
        opcode_encoding.sub_imm_from_acc,
        opcode_encoding.cmp_imm_with_acc,
        => {
            instruction_parts = try allocator.alloc([]const u8, 6);
            instruction_parts[0] = opcode;
            instruction_parts[1] = " ";
            instruction_parts[2] = "ax";
            instruction_parts[3] = ", ";
            instruction_parts[4] = try std.fmt.allocPrint(allocator, "{d}", .{instruction.data});
            instruction_parts[5] = "\n";
        },
        opcode_encoding.imm_to_from_with => {
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

    disp: u16,

    // opcode_extension octal value, for add, sub, cmp to reg/mem, opcode extension
    // 3 bits
    opc_ext: u8,

    // sign extension bit, for add, sub, cmp operations from register/memory
    // 1 bit
    s: u8,

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
    imm_to_from_with = 0b100000,

    mov_normal = 0b100010,
    mov_imm_to_reg = 0b1011,

    add_normal = 0b000000,
    // add_imm_to = 0b100000,
    add_imm_to_acc = 0b0000010,

    sub_normal = 0b001010,
    // sub_imm_from = 0b100000,
    sub_imm_from_acc = 0b0010110,

    cmp_normal = 0b001110,
    // cmp_imm_with = 0b100000,
    cmp_imm_with_acc = 0b0011110,
};

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

test "decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const data = [_]u8{ 0b10001010, 0b00000000 };
    const assembly = try decode(allocator, data);
    defer assembly.deinit();
    print("assembly: \n{s}\n", .{assembly.items});
}
