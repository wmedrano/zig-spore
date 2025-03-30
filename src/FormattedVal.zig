const std = @import("std");

const ByteCodeFunction = @import("ByteCodeFunction.zig");
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

const FormattedVal = @This();

val: Val,
vm: *const Vm,

pub fn format(
    self: FormattedVal,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    switch (self.val._repr) {
        .void => try writer.print("<void>", .{}),
        .bool => |x| try writer.print("{any}", .{x}),
        .int => |x| try writer.print("{any}", .{x}),
        .float => |x| try writer.print("{any}", .{x}),
        .string => {
            const string = try self.val.toZig([]const u8, self.vm);
            try writer.print("\"{s}\"", .{string});
        },
        .symbol => {
            const symbol = try self.val.toZig(Symbol, self.vm);
            try writer.print("{any}", .{symbol});
        },
        .key => {
            const key = try self.val.toZig(Symbol.Key, self.vm);
            try writer.print("{any}", .{key});
        },
        .list => {
            const list = try self.val.toZig([]const Val, self.vm);
            try writer.print("(", .{});
            for (list, 0..list.len) |v, idx| {
                if (idx == 0) {
                    try writer.print("{any}", .{v.formatted(self.vm)});
                } else {
                    try writer.print(" {any}", .{v.formatted(self.vm)});
                }
            }
            try writer.print(")", .{});
        },
        .function => |f| {
            try writer.print("(native-function {s})", .{f.name});
        },
        .bytecode_function => |id| {
            const f = self.vm.objects.get(ByteCodeFunction, id).?;
            try writer.print("(function {s})", .{f.name});
        },
    }
}
