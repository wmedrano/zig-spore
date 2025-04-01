const std = @import("std");

const ByteCodeFunction = Val.ByteCodeFunction;
const NativeFunction = Val.NativeFunction;
const Symbol = Val.Symbol;
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const Error = @import("root.zig").Error;

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
        .void => try writer.print("(<void>)", .{}),
        .bool => |x| try writer.print("{any}", .{x}),
        .int => |x| try writer.print("{any}", .{x}),
        .float => |x| try writer.print("{any}", .{x}),
        .string => {
            const string = self.val.toZig([]const u8, self.vm) catch {
                return writer.print("(<invalid-string>)", .{});
            };
            try writer.print("\"{s}\"", .{string});
        },
        .symbol => {
            const symbol = self.val.toZig(Symbol, self.vm) catch {
                return writer.print("(<invalid-symbol>)", .{});
            };
            try writer.print("{any}", .{symbol});
        },
        .key => {
            const key = self.val.toZig(Symbol.Key, self.vm) catch {
                return writer.print("(<invalid-key>)", .{});
            };
            try writer.print("{any}", .{key});
        },
        .list => {
            const list = self.val.toZig([]const Val, self.vm) catch {
                return writer.print("(<invalid-list>)", .{});
            };
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
            const f = self.vm.objects.get(ByteCodeFunction, id) orelse {
                return writer.print("(<invalid-function>)", .{});
            };
            try writer.print("(function {s})", .{f.name});
        },
    }
}

test "void" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectFmt(
        "(<void>)",
        "{any}",
        .{Val.init().formatted(&vm)},
    );
}

test "bool" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectFmt(
        "true",
        "{any}",
        .{(try Val.fromZig(&vm, true)).formatted(&vm)},
    );
    try std.testing.expectFmt(
        "false",
        "{any}",
        .{(try Val.fromZig(&vm, false)).formatted(&vm)},
    );
}

test "int" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectFmt(
        "123",
        "{any}",
        .{(try Val.fromZig(&vm, 123)).formatted(&vm)},
    );
}

test "float" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectFmt(
        "1.5e0",
        "{any}",
        .{(try Val.fromZig(&vm, 1.5)).formatted(&vm)},
    );
    try std.testing.expectFmt(
        "1.2345e3",
        "{any}",
        .{(try Val.fromZig(&vm, 1234.5)).formatted(&vm)},
    );
}

test "string" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const val = try Val.fromZig(&vm, @as([]const u8, "hello world"));
    try std.testing.expectFmt(
        "\"hello world\"",
        "{any}",
        .{val.formatted(&vm)},
    );
}

test "symbol" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const symbol = try Symbol.fromStr("my-symbol");
    const val = try Val.fromZig(&vm, symbol);
    try std.testing.expectFmt(
        "my-symbol",
        "{any}",
        .{val.formatted(&vm)},
    );
}

test "quoted symbol" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const symbol = try Symbol.fromStr("''my-symbol");
    try std.testing.expectEqual(2, symbol.quotes());
    const val = try Val.fromZig(&vm, symbol);
    try std.testing.expectFmt(
        "''my-symbol",
        "{any}",
        .{val.formatted(&vm)},
    );
}

test "key" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const key = Symbol.Key{ .name = "my-key" };
    const val = try Val.fromZig(&vm, key);
    try std.testing.expectFmt(
        ":my-key",
        "{any}",
        .{val.formatted(&vm)},
    );
}

test "list" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const list = [_]Val{
        try Val.fromZig(&vm, 123),
        try Val.fromZig(&vm, true),
        try Val.fromZig(&vm, @as([]const u8, "hello")),
    };
    const val = try Val.fromZig(&vm, @as([]const Val, &list));
    try std.testing.expectFmt(
        "(123 true \"hello\")",
        "{any}",
        .{val.formatted(&vm)},
    );
}

test "empty list" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const list = [_]Val{};
    const val = try Val.fromZig(&vm, @as([]const Val, &list));
    try std.testing.expectFmt(
        "()",
        "{any}",
        .{val.formatted(&vm)},
    );
}

test "nested list" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const list1 = [_]Val{
        try Val.fromZig(&vm, 123),
        try Val.fromZig(&vm, true),
    };
    const list2 = [_]Val{
        try Val.fromZig(&vm, @as([]const Val, &list1)),
        try Val.fromZig(&vm, @as([]const u8, "hello")),
    };
    const val = try Val.fromZig(&vm, @as([]const Val, &list2));
    try std.testing.expectFmt(
        "((123 true) \"hello\")",
        "{any}",
        .{val.formatted(&vm)},
    );
}

fn myFunc(_: *Vm) Error!Val {
    return Val.init();
}

test "native function" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.global.registerFunction(&vm, NativeFunction.init("my-func", myFunc));
    const val = try vm.evalStr(Val, "my-func");
    try std.testing.expectFmt(
        "(native-function my-func)",
        "{any}",
        .{val.formatted(&vm)},
    );
}

test "bytecode function" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.evalStr(void, "(defun foo () 42)");
    const val = try vm.evalStr(Val, "foo");
    try std.testing.expectFmt(
        "(function foo)",
        "{any}",
        .{val.formatted(&vm)},
    );
}
