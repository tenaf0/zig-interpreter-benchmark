const std = @import("std");

const instr = @import("instr.zig");
const parse = @import("parse.zig");

const Allocator = std.mem.Allocator;

const is_direct_threaded = false;
const enable_debug_print = false;
const interactive = false;

const writer = std.io.getStdOut().writer();

const Stack = struct {
    locals: [8]i64,
    data: [64]i64,
    top: u7 = 0,

    fn push(stack: *Stack, data: i64) void {
        stack.data[stack.top] = data;
        stack.top += 1;
    }

    fn pop(stack: *Stack) i64 {
        stack.top -= 1;
        return stack.data[stack.top];
    }

    fn print(stack: *Stack) !void {
        try writer.print("[", .{});
        for (stack.locals) |l| {
            try writer.print("{d}, ", .{l});
        }
        try writer.print("] ", .{});

        var i: usize = 0;
        while (i < stack.top) : (i += 1) {
            try writer.print("{d}, ", .{stack.data[i]});
        }
        try writer.print("\n", .{});
    }
};

fn execute(program: instr.Program, stack: *Stack) !void {
    var pc: u64 = 0;
    while (pc < program.len) {
        if (enable_debug_print) {
            try writer.print("pc: {d} stack: ", .{pc});
            try stack.print();
        }

        if (enable_debug_print and interactive) {
            _ = std.io.getStdIn().reader().readByte() catch {};
        }

        switch (program[pc].instruction) {
            instr.Command.add => {
                stack.push(stack.pop() + stack.pop());

                pc += 2;
            },
            instr.Command.mul => {
                stack.push(stack.pop() * stack.pop());

                pc += 2;
            },
            instr.Command.c => {
                stack.push(program[pc + 1].param);

                pc += 2;
            },
            instr.Command.load => {
                const index = program[pc + 1].param;
                stack.push(stack.locals[@intCast(index)]);

                pc += 2;
            },
            instr.Command.save => {
                const index = program[pc + 1].param;
                stack.locals[@intCast(index)] = stack.pop();

                pc += 2;
            },
            instr.Command.goto => {
                const rel_pc: i64 = program[pc + 1].param;

                const casted_pc: i64 = @as(u32, @truncate(pc));
                pc = @intCast(casted_pc + 2 * rel_pc);
            },
            instr.Command.jmp_eq => {
                if (stack.pop() == stack.pop()) {
                    const rel_pc: i64 = program[pc + 1].param;

                    const casted_pc: i64 = @as(u32, @truncate(pc));
                    pc = @intCast(casted_pc + 2 * rel_pc);
                } else {
                    pc += 2;
                }
            },
            instr.Command.jmp_lt => {
                if (stack.pop() > stack.pop()) {
                    const rel_pc: i64 = program[pc + 1].param;

                    const casted_pc: i64 = @as(u32, @truncate(pc));
                    pc = @intCast(casted_pc + 2 * rel_pc);
                } else {
                    pc += 2;
                }
            },
            instr.Command.print => {
                const param = stack.pop();
                try writer.print("{d}\n", .{param});

                pc += 2;
            },
            instr.Command.nop => {
                pc += 2;
            },
        }
    }
}

// Functions for direct threaded interpreter

const DirectThreadedProgram = union { fn_ptr: *const fn (*Stack, [*]DirectThreadedProgram) void, param: i64 };

fn mapProgramToDirectThreaded(allocator: *Allocator, program: instr.Program) ![*]DirectThreadedProgram {
    var buffer = try allocator.alloc(DirectThreadedProgram, program.len);

    var i: u64 = 0;
    while (i < program.len) : (i += 2) {
        buffer[i] = switch (program[i].instruction) {
            instr.Command.add => .{ .fn_ptr = &add },
            instr.Command.mul => .{ .fn_ptr = &mul },
            instr.Command.c => .{ .fn_ptr = &c },
            instr.Command.load => .{ .fn_ptr = &load },
            instr.Command.save => .{ .fn_ptr = &save },
            instr.Command.goto => .{ .fn_ptr = &goto },
            instr.Command.jmp_eq => .{ .fn_ptr = &jmp_eq },
            instr.Command.jmp_lt => .{ .fn_ptr = &jmp_lt },
            instr.Command.print => .{ .fn_ptr = &print },
            instr.Command.nop => .{ .fn_ptr = &nop },
        };
        buffer[i + 1] = .{ .param = program[i + 1].param };
    }

    return buffer.ptr;
}

inline fn goto_next_fn(stack: *Stack, instr_data: [*]DirectThreadedProgram, rel_pc: i64) void {
    const ptr = if (rel_pc > 0) instr_data + @as(usize, @intCast(rel_pc)) else instr_data - @as(usize, @intCast(-rel_pc));
    const fn_ptr = ptr[0].fn_ptr;

    // fn_ptr(stack, instr_data);
    if (enable_debug_print) {
        stack.print() catch {};
    }
    @call(.always_tail, fn_ptr, .{ stack, ptr });
}

fn add(stack: *Stack, instr_data: [*]DirectThreadedProgram) void {
    stack.push(stack.pop() + stack.pop());

    goto_next_fn(stack, instr_data, 2);
}
fn mul(stack: *Stack, instr_data: [*]DirectThreadedProgram) void {
    stack.push(stack.pop() * stack.pop());

    goto_next_fn(stack, instr_data, 2);
}
fn c(stack: *Stack, instr_data: [*]DirectThreadedProgram) void {
    stack.push(instr_data[1].param);

    goto_next_fn(stack, instr_data, 2);
}
fn load(stack: *Stack, instr_data: [*]DirectThreadedProgram) void {
    const index = instr_data[1].param;
    stack.push(stack.locals[@intCast(index)]);

    goto_next_fn(stack, instr_data, 2);
}
fn save(stack: *Stack, instr_data: [*]DirectThreadedProgram) void {
    const index = instr_data[1].param;
    stack.locals[@intCast(index)] = stack.pop();

    goto_next_fn(stack, instr_data, 2);
}
fn goto(stack: *Stack, instr_data: [*]DirectThreadedProgram) void {
    const rel_pc: i64 = instr_data[1].param;

    goto_next_fn(stack, instr_data, 2 * rel_pc);
}
fn jmp_eq(stack: *Stack, instr_data: [*]DirectThreadedProgram) void {
    var rel_pc: i64 = undefined;
    if (stack.pop() == stack.pop()) {
        rel_pc = 2 * instr_data[1].param;
    } else {
        rel_pc = 2;
    }

    goto_next_fn(stack, instr_data, rel_pc);
}
fn jmp_lt(stack: *Stack, instr_data: [*]DirectThreadedProgram) void {
    var rel_pc: i64 = undefined;
    if (stack.pop() > stack.pop()) {
        rel_pc = 2 * instr_data[1].param;
    } else {
        rel_pc = 2;
    }

    goto_next_fn(stack, instr_data, rel_pc);
}
fn print(stack: *Stack, instr_data: [*]DirectThreadedProgram) void {
    const param = stack.pop();
    writer.print("{d}\n", .{param}) catch {};

    goto_next_fn(stack, instr_data, 2);
}

fn nop(stack: *Stack, _: [*]DirectThreadedProgram) void {
    if (enable_debug_print) {
        stack.print() catch {};
    }
    return;
}

fn execute_direct_threaded(instr_data: [*]DirectThreadedProgram, stack: *Stack) !void {
    instr_data[0].fn_ptr(stack, instr_data);
    return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var list = std.ArrayList(instr.Instr).init(allocator);
    const program: instr.Program = try parse.parse(&list); //arr[0..arr.len];

    var stack = Stack{
        .locals = undefined,
        .data = undefined,
    };

    if (is_direct_threaded) {
        var direct_threaded_code = try mapProgramToDirectThreaded(&allocator, program);

        var is_instr = true;
        for (direct_threaded_code[0..program.len]) |direct_c| {
            const ptr: u32 = if (is_instr) @truncate(@intFromPtr(direct_c.fn_ptr)) else undefined;
            try writer.print("{d}\n", .{(if (is_instr) @as(i64, @intCast(ptr)) else direct_c.param)});
            is_instr = !is_instr;
        }

        try execute_direct_threaded(direct_threaded_code, &stack);
    } else {
        try execute(program, &stack);
    }

    try stack.print();
}
