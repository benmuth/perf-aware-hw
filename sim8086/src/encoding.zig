const std = @import("std");
const print = std.debug.print;

pub fn decode(allocator: std.mem.Allocator, buf: []u8) !std.ArrayList(u8) {
    var assembly = std.ArrayList(u8).init(allocator);

    var i: usize = 0;
    while (i < buf.len) : (i += 2) { // NOTE: hardcoded to 2 byte instr
        var instruction_bytes = [2]u8{ buf[i], buf[i + 1] };
        var instruction = try parseInstruction(instruction_bytes);
        var line = try binToAsm(allocator, instruction);
        try assembly.appendSlice(line);
    }
    return assembly;
}

const ReadError = error{FailedToParse};

/// takes 2 bytes of binary data and returns an instruction with the six fields of the mov instruction filled out
pub fn parseInstruction(bytes: [2]u8) ReadError!Instruction {
    // NOTE: hardcoded to 2 byte instructions
    const b1 = bytes[0];
    const b2 = bytes[1];
    var parsed_instruction = Instruction{};

    parsed_instruction.opcode = (b1 & 0b11111100) >> 2;
    parsed_instruction.d = (b1 & 0b00000010) >> 1;
    parsed_instruction.w = (b1 & 0b00000001) >> 0;
    parsed_instruction.mod = (b2 & 0b11000000) >> 6;
    parsed_instruction.reg = (b2 & 0b00111000) >> 3;
    parsed_instruction.rm = (b2 & 0b00000111) >> 0;
    return parsed_instruction;
}

/// takes an instruction and returns a line of assembly
pub fn binToAsm(allocator: std.mem.Allocator, instruction: Instruction) ![]const u8 {
    // flip src and dest register based on d bit
    var regs = [2]u8{ instruction.reg, instruction.rm };
    if (instruction.d == 0) {
        regs[0] = instruction.rm;
        regs[1] = instruction.reg;
    }
    var regs_asm: [2][]const u8 = undefined;
    for (regs, 0..) |reg, i| {
        regs_asm[i] = reg_arr[reg][instruction.w];
    }

    var opcode: []const u8 = undefined;
    switch (@as(opcodes, @enumFromInt(instruction.opcode))) {
        opcodes.MOV => opcode = "mov",
    }

    // put parts together
    const asm_instruction = [_][]const u8{
        opcode,
        " ",
        regs_asm[0],
        ", ",
        regs_asm[1],
        "\n",
    };

    const header = try std.mem.concat(allocator, u8, &asm_instruction);
    return header;
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

// holds the binary values of each field of an instruction
const Instruction = struct {
    opcode: u8 = 0,
    d: u8 = 0,
    w: u8 = 0,
    mod: u8 = 0,
    reg: u8 = 0,
    rm: u8 = 0,

    pub fn printMe(self: *Instruction) void {
        const fields = std.meta.fields(@TypeOf(self.*));
        inline for (fields) |field| {
            print("{s}: {b} ", .{ field.name, @field(self.*, field.name) });
        }
        print("\n", .{});
    }
};

// TODO: expand to more opcodes
const opcodes = enum(u6) { MOV = 0b100010 };

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

// test ""
