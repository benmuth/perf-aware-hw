const std = @import("std");
const print = std.debug.print;

pub fn decode(allocator: std.mem.Allocator, buf: []u8) !std.ArrayList(u8) {
    var assembly = std.ArrayList(u8).init(allocator);

    var i: usize = 0;
    while (i < buf.len) : (i += 2) { // NOTE: hardcoded to 2 byte instr
        var instruction_bytes = [2]u8{ buf[i], buf[i + 1] };
        print("instruction bytes: {0b}\n", .{instruction_bytes});
        var instruction = try parseInstruction(instruction_bytes);
        print("instruction: {any}\n", .{instruction});
        var line = try binToAsm(allocator, instruction);
        print("line: {s}\n", .{line});
        try assembly.appendSlice(line);
    }
    return assembly;
}

const ReadError = error{FailedToParse};

// takes 2 bytes of binary data and returns an instruction with the six fields of the mov instruction filled out
// NOTE: hardcoded to 2 byte instructions
pub fn parseInstruction(bytes: [2]u8) ReadError!Instruction {
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

// takes an instruction and returns a line of assembly
pub fn binToAsm(allocator: std.mem.Allocator, instruction: Instruction) ![]const u8 {
    var regs = [2]u8{ instruction.reg, instruction.rm };
    if (instruction.d == 0) {
        regs[0] = instruction.rm;
        regs[1] = instruction.reg;
    }
    var regsAsm = [2][]const u8{ "", "" };
    for (regs, 0..) |reg, i| {
        switch (reg) {
            0b000 => {
                if (instruction.w == 0) {
                    regsAsm[i] = "al";
                } else {
                    regsAsm[i] = "ax";
                }
            },
            0b001 => {
                if (instruction.w == 0) {
                    regsAsm[i] = "cl";
                } else {
                    regsAsm[i] = "cx";
                }
            },
            0b010 => {
                if (instruction.w == 0) {
                    regsAsm[i] = "dl";
                } else {
                    regsAsm[i] = "dx";
                }
            },
            0b011 => {
                if (instruction.w == 0) {
                    regsAsm[i] = "bl";
                } else {
                    regsAsm[i] = "bx";
                }
            },
            0b100 => {
                if (instruction.w == 0) {
                    regsAsm[i] = "ah";
                } else {
                    regsAsm[i] = "sp";
                }
            },
            0b101 => {
                if (instruction.w == 0) {
                    regsAsm[i] = "ch";
                } else {
                    regsAsm[i] = "bp";
                }
            },
            0b110 => {
                if (instruction.w == 0) {
                    regsAsm[i] = "dh";
                } else {
                    regsAsm[i] = "si";
                }
            },
            0b111 => {
                if (instruction.w == 0) {
                    regsAsm[i] = "bh";
                } else {
                    regsAsm[i] = "di";
                }
            },
            else => return ReadError.FailedToParse,
        }
    }

    var opcode: []const u8 = undefined;
    switch (@as(opcodes, @enumFromInt(instruction.opcode))) {
        opcodes.MOV => opcode = "mov",
    }

    const asm_instruction = [_][]const u8{
        opcode,
        " ",
        regsAsm[0],
        ", ",
        regsAsm[1],
        "\n",
    };

    const header = try std.mem.concat(allocator, u8, &asm_instruction);
    return header;
}

// used to switch
const instruction_fields = enum(u8) { opcode, d, w, mod, reg, rm };

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
