const std = @import("std");
const print = std.debug.print;

pub fn decode(buf: []u8) ReadError![]const u8 {
    // std.debug.print("Decoding...\n", .{});
    // std.debug.print("buf: {b}\n", .{buf});

    // var assembly = "bits 16\n";
    var assembly = std.ArrayList(u8).init(std.heap.GeneralPurposeAllocator);
    defer assembly.deinit();
    assembly.appendSlice("bits 16\n");

    var i: usize = 0;
    while (i < buf.len) : (i += 2) { // NOTE: hardcoded to 2 byte instr
        var instrBytes = [2]u8{ buf[i], buf[i + 1] };
        var instr = parseInstruction(instrBytes) catch {
            print("ERROR: failed to parse instructions", .{});
            return;
        };
        var line = try binToAsm(instr);
        assembly.appendSlice(line);
    }
    return assembly;
}

const ReadError = error{FailedToParse};

// takes 2 bytes and returns an instruction with the six fields of the mov
// instruction filled out
// NOTE: hardcoded to 2 byte instructions
pub fn parseInstruction(bytes: [2]u8) ReadError!instruction {
    const b1 = bytes[0];
    const b2 = bytes[1];
    // print("original bytes: {b}, {b}\n", .{ b1, b2 });
    var parsedInstruction = instruction{};
    const fields = std.meta.fields(instrFields);
    // const fields = @typeInfo(instruction).Struct.fields;
    inline for (fields) |field| {
        // NOTE: switch might not be necessary?
        switch (field.value) {
            @intFromEnum(instrFields.opcode) => {
                parsedInstruction.opcode = (b1 & 0b11111100) >> 2;
            },
            @intFromEnum(instrFields.d) => {
                parsedInstruction.d = (b1 & 0b00000010) >> 1;
            },
            @intFromEnum(instrFields.w) => {
                parsedInstruction.w = (b1 & 0b00000001) >> 0;
            },
            @intFromEnum(instrFields.mod) => {
                parsedInstruction.mod = (b2 & 0b11000000) >> 6;
            },
            @intFromEnum(instrFields.reg) => {
                parsedInstruction.reg = (b2 & 0b00111000) >> 3;
            },
            @intFromEnum(instrFields.rm) => {
                parsedInstruction.rm = (b2 & 0b00000111) >> 0;
            },
            else => {
                return ReadError.FailedToParse;
            },
        }
    }

    return parsedInstruction;
}

// takes an instruction and returns a line of assembly
pub fn binToAsm(instr: instruction) ![]const u8 {
    var regs = [2]u8{ instr.reg, instr.rm };
    if (instr.d == 0) {
        regs[0] = instr.rm;
        regs[1] = instr.reg;
    }
    var regsAsm = [2][]const u8{ "", "" };
    for (regs, 0..) |reg, i| {
        switch (reg) {
            0b000 => {
                if (instr.w == 0) {
                    regsAsm[i] = "al";
                } else {
                    regsAsm[i] = "ax";
                }
            },
            0b001 => {
                if (instr.w == 0) {
                    regsAsm[i] = "cl";
                } else {
                    regsAsm[i] = "cx";
                }
            },
            0b010 => {
                if (instr.w == 0) {
                    regsAsm[i] = "dl";
                } else {
                    regsAsm[i] = "dx";
                }
            },
            0b011 => {
                if (instr.w == 0) {
                    regsAsm[i] = "bl";
                } else {
                    regsAsm[i] = "bx";
                }
            },
            0b100 => {
                if (instr.w == 0) {
                    regsAsm[i] = "ah";
                } else {
                    regsAsm[i] = "sp";
                }
            },
            0b101 => {
                if (instr.w == 0) {
                    regsAsm[i] = "ch";
                } else {
                    regsAsm[i] = "bp";
                }
            },
            0b110 => {
                if (instr.w == 0) {
                    regsAsm[i] = "dh";
                } else {
                    regsAsm[i] = "si";
                }
            },
            0b111 => {
                if (instr.w == 0) {
                    regsAsm[i] = "bh";
                } else {
                    regsAsm[i] = "di";
                }
            },
            else => return ReadError.FailedToParse,
        }
    }

    var opcode = "opc"; // this will be overwritten
    switch (@as(opcodes, @enumFromInt(instr.opcode))) {
        // opcodes.MOV => print("mov\n", .{}),
        opcodes.MOV => opcode = "mov",
    }
    return opcode ++ " " ++ regsAsm[0] + ", " ++ regsAsm[1] ++ "\n";
    // print("{s} {s}, {s}\n", .{ opcode, regsAsm[0], regsAsm[1] });
}

// used to switch
pub const instrFields = enum(u8) { opcode, d, w, mod, reg, rm };

// holds the binary values of each field of an instruction
const instruction = struct {
    opcode: u8 = 0,
    d: u8 = 0,
    w: u8 = 0,
    mod: u8 = 0,
    reg: u8 = 0,
    rm: u8 = 0,

    pub fn printMe(self: *instruction) void {
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
