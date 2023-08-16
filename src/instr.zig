pub const Command = enum(u8) { add, mul, c, load, save, goto, jmp_eq, jmp_lt, print, nop };
pub const Instr = union { instruction: Command, param: i64 };

pub const Program = []Instr;

// Code sample:
// c 2
// c 6
// add
// c 3
// add
// print
