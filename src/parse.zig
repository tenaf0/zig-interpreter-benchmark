const std = @import("std");
const instr = @import("instr.zig");

const expect = std.testing.expect;
const eql = std.meta.eql;

const writer = std.io.getStdOut().writer();

pub fn parse(list: anytype, file_name: [*:0]const u8) !instr.Program {
    const file = try std.fs.openFileAbsoluteZ(file_name, .{});
    defer file.close();

    var buffer: [128]u8 = undefined;
    var bufferStream = std.io.FixedBufferStream([]u8){ .buffer = &buffer, .pos = 0 };
    var reader = file.reader();
    var line_no: usize = 0;

    errdefer {
        writer.print("Error at line {d}\n", .{line_no}) catch {};
    }
    while (try nextLine(reader, &bufferStream)) |line| {
        line_no += 1;
        if (split(line)) |program_line| {
            const slice: [:0]const u8 = program_line.command[0..countTillZero(&program_line.command) :0];
            const command = std.meta.stringToEnum(instr.Command, slice) orelse return error.ParseError;

            try list.*.append(instr.Instr{ .instruction = command });
            try list.*.append(instr.Instr{ .param = program_line.param });
        } else |err| switch (err) {
            error.EmptyLine => {},
            else => {
                return err;
            },
        }
    }

    return list.items;
}

fn nextLine(reader: anytype, bufferStream: anytype) !?[]const u8 {
    bufferStream.*.reset();
    reader.streamUntilDelimiter(bufferStream.*.writer(), '\n', null) catch return null;

    return bufferStream.buffer[0..bufferStream.pos];
}

const ProgramLine = struct { command: [16]u8, param: i64 };

fn split(line: []const u8) !ProgramLine {
    if (line.len == 0) {
        return error.EmptyLine;
    }

    var buffer1: [24]u8 = undefined;
    var buffer1_len: usize = 0;
    var buffer2: [24]u8 = undefined;
    var buffer2_len: usize = 0;

    var seenSpace = false;
    var isComment = false;
    for (line) |c| {
        if (c == '/') {
            if (!isComment) {
                isComment = true;
            } else {
                break;
            }
        } else if (c == ' ') {
            seenSpace = true;
        } else if (c != ' ' and !seenSpace) {
            buffer1[buffer1_len] = c;
            buffer1_len += 1;
        } else {
            buffer2[buffer2_len] = c;
            buffer2_len += 1;
        }
    }

    var ret = ProgramLine{ .command = undefined, .param = try std.fmt.parseInt(i64, buffer2[0..buffer2_len], 10) };
    std.mem.copy(u8, &ret.command, buffer1[0 .. buffer1_len + 1]);
    ret.command[buffer1_len] = 0;

    return ret;
}

test "split line" {
    const line: []const u8 = "save 2";

    const prog_line = try split(line);
    try expect(std.mem.eql(u8, &prog_line.command, "save"));
    try expect(prog_line.param == 2);
}

fn countTillZero(str: []const u8) usize {
    var i: usize = 0;
    while (i < str.len) : (i += 1) {
        if (str[i] == 0) {
            break;
        }
    }

    return i;
}

test "count till 0-elem" {
    const str = [_]u8{ 1, 2, 3, 0, 6, 2, 0, 0 };

    try expect(countTillZero(&str) == 4);
}
