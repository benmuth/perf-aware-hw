const std = @import("std");
const print = std.debug.print;

const AssemblyIterator = struct {
    buf: []u8,
    index: usize = 0,

    fn next(self: *AssemblyIterator) ?Instruction {
        const index = self.index;

        for (index..self.buf.len) |i| {
            const buf_end = if (i + 7 < self.buf.len) i + 7 else self.buf.len;
            const parsed_instruction = parseInstruction(self.buf[i..buf_end]) catch return null;
            self.index += parsed_instruction.size;
            return parsed_instruction;
        }
        return null;
    }
};

pub fn decode(allocator: std.mem.Allocator, buf: []u8) !std.ArrayList(u8) {
    var assembly = std.ArrayList(u8).init(allocator);

    var iter = AssemblyIterator{ .buf = buf };

    // var i: usize = 0;
    while (iter.next()) |instruction| { // NOTE: hardcoded to 2 byte instr
        // var instruction_bytes = [2]u8{ buf[i], buf[i + 1] };
        // var instruction = try parseInstruction(instruction_bytes);
        var line = try binToAsm(allocator, instruction);
        try assembly.appendSlice(line);
    }
    print("assembly: {s}\n", .{assembly.items});
    return assembly;
}

const ReadError = error{FailedToParse};

/// takes binary data and returns an instruction
pub fn parseInstruction(bytes: []u8) !Instruction {
    var parsed_instruction: Instruction = undefined;

    parsed_instruction.opcode = try parseOpcode(bytes[0]);
    switch (parsed_instruction.opcode) {
        opcode_encoding.normal_mov => {
            parsed_instruction.d = (bytes[0] & 0b00000010) >> 1;
            parsed_instruction.w = (bytes[0] & 0b00000001) >> 0;
            parsed_instruction.mod = (bytes[1] & 0b11000000) >> 6;
            parsed_instruction.reg = (bytes[1] & 0b00111000) >> 3;
            parsed_instruction.rm = (bytes[1] & 0b00000111) >> 0;
            switch (parsed_instruction.mod) {
                0b00, 0b11 => parsed_instruction.size = 2,
                0b01 => parsed_instruction.size = 3,
                0b10 => parsed_instruction.size = 4,
                else => unreachable,
            }
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
                const hi = @shlExact(@as(u16, bytes[1]), 8);
                parsed_instruction.data = hi | @as(u16, bytes[2]);
            }
        },
    }
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

/// takes an instruction and returns a line of assembly
pub fn binToAsm(allocator: std.mem.Allocator, instruction: Instruction) ![]const u8 {
    // flip src and dest register based on d bit
    // var regs: [2]u8 = undefined;
    var dst: u8 = undefined;
    var src: u8 = undefined;

    // var asm_instruction: [][]const u8 = undefined;

    if (instruction.opcode == opcode_encoding.normal_mov) {
        dst = instruction.reg;
        src = instruction.rm;
        // flip src and dst if d isn't set
        if (instruction.d == 0) {
            src = instruction.reg;
            dst = instruction.rm;
        }
    } else if (instruction.opcode == opcode_encoding.imm_to_reg) {
        dst = instruction.reg;
    }

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
            instruction_parts[2] = reg_arr[dst][instruction.w];
            instruction_parts[3] = ", ";
            instruction_parts[4] = reg_arr[src][instruction.w];
            instruction_parts[5] = "\n";
        },
        opcode_encoding.imm_to_reg => {
            instruction_parts = try allocator.alloc([]const u8, 6);
            instruction_parts[0] = opcode;
            instruction_parts[1] = " ";
            instruction_parts[2] = reg_arr[dst][instruction.w];
            instruction_parts[3] = ", ";
            instruction_parts[4] = try std.fmt.allocPrint(allocator, "{d}", .{instruction.data});
            instruction_parts[5] = "\n";
        },
    }

    const instruction_str = try std.mem.concat(allocator, u8, instruction_parts);
    return instruction_str;
}

const reg_arr = [8][2][]const u8{
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

const registers = enum {
    AL,
    CL,
    DL,
    BL,
    AH,
    CH,
    DH,
    BH,
    AX,
    CX,
    DX,
    BX,
    SP,
    BP,
    SI,
    DI,
};

const mod = enum(u2) {
    mem,
    mem_8,
    mem_16,
    reg,
};

// test ""
