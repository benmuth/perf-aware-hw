const std = @import("std");
const print = std.debug.print;

pub const InstructionParser = struct {
    buf: []const u8,
    index: usize = 0,

    pub fn next(self: *InstructionParser) ?Instruction {
        const index = self.index;
        const buf_end = if (index + 7 < self.buf.len) index + 7 else self.buf.len;

        const parsed_instruction = parseInstruction(self.buf[index..buf_end]) catch |err| {
            switch (err) {
                error.NoData => {
                    print("no data!\n", .{});
                },
                error.FailedToParse => {
                    print("failed to parse\n", .{});
                },
            }
            return null;
        };
        self.index += parsed_instruction.size;
        return parsed_instruction;
        // }
    }
};

pub fn decode(allocator: std.mem.Allocator, data: []const u8) !std.ArrayList(u8) {
    var assembly = std.ArrayList(u8).init(allocator);

    var iter = InstructionParser{ .buf = data };

    while (iter.next()) |instruction| {
        const line = try instructionToAsm(allocator, instruction);
        try assembly.appendSlice(line);
        try assembly.appendSlice("\n");
    }
    // print("assembly:\n{s}\n", .{assembly.items});
    return assembly;
}

pub fn parseInstruction(bytes: []const u8) !Instruction {
    if (bytes.len == 0) return error.NoData;

    var parsed_instruction: Instruction = undefined;
    parsed_instruction.opcode = parseOpcode(bytes[0]);
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
        opcode_encoding.imm_reg_or_mem => {
            parsed_instruction.s = (bytes[0] & 0b0000_0010) >> 1;
            parsed_instruction.w = (bytes[0] & 0b0000_0001) >> 0;
            parsed_instruction.mod = (bytes[1] & 0b1100_0000) >> 6;
            parsed_instruction.opc_ext = (bytes[1] & 0b0011_1000) >> 3;
            parsed_instruction.rm = (bytes[1] & 0b0000_0111) >> 0;

            var size: u8 = 2;
            switch (parsed_instruction.mod) {
                0b00 => {
                    // size += 1;
                    if (parsed_instruction.rm == 0b110) {
                        size += 2;
                    }
                },
                0b01 => {
                    parsed_instruction.disp = bytes[2];
                    size += 1;
                },
                0b10 => {
                    const hi = @shlExact(@as(u16, bytes[3]), 8);
                    parsed_instruction.disp = hi | @as(u16, bytes[2]);
                    size += 2;
                },
                0b11 => {
                    // size += 1;
                },
                else => {
                    print("Error: failed to parse mod field\n", .{});
                    print("parsed instruction: {}\n", .{parsed_instruction});
                    return error.FailedToParse;
                },
            }

            if (parsed_instruction.s == 0 and parsed_instruction.w == 1) {
                const hi_data = @shlExact(@as(u16, bytes[size + 1]), 8);
                parsed_instruction.data = hi_data | @as(u16, bytes[size]);
                size += 2;
            } else {
                parsed_instruction.data = bytes[size];
                size += 1;
            }
            parsed_instruction.size = size;
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
        // it's a jump
        else => {
            parsed_instruction.size = 2;
            parsed_instruction.data = bytes[1];
        },
    }
    return parsed_instruction;
}

fn parseOpcode(byte: u8) opcode_encoding {
    // add, sub, or cmp, look at second byte to know
    if (((byte & 0b1111_1100) ^ 0b1000_0000) == 0) {
        return opcode_encoding.imm_reg_or_mem;
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

    if (((byte & 0b1111_1100) ^ 0b0011_1000) == 0) {
        return opcode_encoding.cmp_normal;
    }
    if (((byte & 0b1111_1110) ^ 0b0011_1100) == 0) {
        return opcode_encoding.cmp_imm_with_acc;
    }

    // parse jumps
    return @enumFromInt(byte);

    // print("Failed to parse opcode\n", .{});
    // print("input byte: {b:0>8}\n", .{byte});
    // return error.FailedToParse;
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
pub fn instructionToAsm(allocator: std.mem.Allocator, instruction: Instruction) ![]const u8 {
    var dst_str: []const u8 = undefined;
    var src_str: []const u8 = undefined;

    var formula: []const u8 = undefined;
    // print("opcode: {any}\n", .{instruction.opcode});
    // print("instruction:\n{any}\n", .{instruction});
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

        opcode_encoding.imm_reg_or_mem => {
            if (instruction.mod == 0b11) {
                dst_str = registers[instruction.rm][instruction.w];
            } else {
                dst_str = try calcAddress(allocator, instruction);
            }
        },

        opcode_encoding.add_imm_to_acc,
        opcode_encoding.sub_imm_from_acc,
        opcode_encoding.cmp_imm_with_acc,
        => {
            // print("ACC UNHANDLED\n", .{});
            // return error.AccUnhandled;
        },
        else => {},
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

        opcode_encoding.imm_reg_or_mem => {
            switch (instruction.opc_ext) {
                0b000 => opcode = "add",
                0b101 => opcode = "sub",
                0b111 => opcode = "cmp",
                else => return error.UnhandledOpcode,
            }
        },
        else => |opc| {
            opcode = @tagName(opc);
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
            instruction_parts = try allocator.alloc([]const u8, 5);
            instruction_parts[0] = opcode;
            instruction_parts[1] = " ";
            instruction_parts[2] = dst_str;
            instruction_parts[3] = ", ";
            instruction_parts[4] = src_str;
        },
        opcode_encoding.mov_imm_to_reg => {
            instruction_parts = try allocator.alloc([]const u8, 5);
            instruction_parts[0] = opcode;
            instruction_parts[1] = " ";
            instruction_parts[2] = dst_str;
            instruction_parts[3] = ", ";
            instruction_parts[4] = try std.fmt.allocPrint(allocator, "{d}", .{instruction.data});
        },
        opcode_encoding.add_imm_to_acc,
        opcode_encoding.sub_imm_from_acc,
        opcode_encoding.cmp_imm_with_acc,
        => {
            instruction_parts = try allocator.alloc([]const u8, 5);
            instruction_parts[0] = opcode;
            instruction_parts[1] = " ";
            instruction_parts[2] = registers[0][instruction.w];
            instruction_parts[3] = ", ";
            instruction_parts[4] = try std.fmt.allocPrint(allocator, "{d}", .{instruction.data});
        },
        opcode_encoding.imm_reg_or_mem => {
            instruction_parts = try allocator.alloc([]const u8, 5);
            instruction_parts[0] = opcode;
            instruction_parts[1] = " ";
            instruction_parts[2] = dst_str;
            instruction_parts[3] = ", ";
            instruction_parts[4] = try std.fmt.allocPrint(allocator, "{d}", .{instruction.data});
        },
        else => {
            instruction_parts = try allocator.alloc([]const u8, 3);
            instruction_parts[0] = opcode;
            instruction_parts[1] = " ";
            instruction_parts[2] = try std.fmt.allocPrint(allocator, "{d}", .{instruction.data});
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

const opcode_encoding = enum(u8) {
    imm_reg_or_mem = 0b100000,

    mov_normal = 0b100010,
    mov_imm_to_reg = 0b1011,

    add_normal = 0b000000,
    add_imm_to_acc = 0b0000010,

    sub_normal = 0b001010,
    sub_imm_from_acc = 0b0010110,

    cmp_normal = 0b001110,
    cmp_imm_with_acc = 0b0011110,

    // jumps
    je = 0b01110100,
    jl = 0b01111100,
    jle = 0b01111110,
    jb = 0b01110010,
    jbe = 0b01110110,
    jp = 0b01111010,
    jo = 0b01110000,
    js = 0b01111000,
    jne = 0b01110101,
    jnl = 0b01111101,
    jnle = 0b01111111,
    jnb = 0b01110011,
    jnbe = 0b01110111,
    jnp = 0b01111011,
    jno = 0b01110001,
    jns = 0b01111001,
    loop = 0b11100010,
    loopz = 0b11100001,
    loopnz = 0b11100000,
    jcxz = 0b11100011,
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
// opcode_encoding.je => |opc| opcode = @tagName(opc),
// opcode_encoding.jl => |opc| opcode = @tagName(opc),
// opcode_encoding.jle => |opc| opcode = @tagName(opc),
// opcode_encoding.jb => |opc| opcode = @tagName(opc),
// opcode_encoding.jbe => |opc| opcode = @tagName(opc),
// opcode_encoding.jp => |opc| opcode = @tagName(opc),
// opcode_encoding.jo => |opc| opcode = @tagName(opc),
// opcode_encoding.js => |opc| opcode = @tagName(opc),
// opcode_encoding.jne => |opc| opcode = @tagName(opc),
// opcode_encoding.jnl => |opc| opcode = @tagName(opc),
// opcode_encoding.jnle => |opc| opcode = @tagName(opc),
// opcode_encoding.jnb => |opc| opcode = @tagName(opc),
// opcode_encoding.jnbe => |opc| opcode = @tagName(opc),
// opcode_encoding.jnp => |opc| opcode = @tagName(opc),
// opcode_encoding.jno => |opc| opcode = @tagName(opc),
// opcode_encoding.jns => |opc| opcode = @tagName(opc),
// opcode_encoding.loop => |opc| opcode = @tagName(opc),
// opcode_encoding.loopz => |opc| opcode = @tagName(opc),
// opcode_encoding.loopnz => |opc| opcode = @tagName(opc),
// opcode_encoding.jcxz => |opc| opcode = @tagName(opc),

// opcode_encoding.je, opcode_encoding.jl, opcode_encoding.jle, opcode_encoding.jb, opcode_encoding.jbe, opcode_encoding.jp, opcode_encoding.jo, opcode_encoding.js, opcode_encoding.jne, opcode_encoding.jnl, opcode_encoding.jnle, opcode_encoding.jnb, opcode_encoding.jnbe, opcode_encoding.jnp, opcode_encoding.jno, opcode_encoding.jns, opcode_encoding.loop, opcode_encoding.loopz, opcode_encoding.loopnz, opcode_encoding.jcxz => |opc| opcode = @tagName(opc),
