pub const Module = @import("Module.zig");
pub const Symbol = @import("Symbol.zig");
pub const Val = @import("Val.zig");
pub const Vm = @import("Vm.zig");

const std = @import("std");

test "can make vm" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
}

test "can run gc" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    try vm.runGc();
    defer vm.deinit();
}

test "eval constant returns constant" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("12");
    try std.testing.expectEqual(Val.fromZig(i64, &vm, 12), actual);
}

test "eval can return symbol" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("'+");
    try std.testing.expectEqual(try Val.fromSymbolStr(&vm, "+"), actual);
}

test "eval multiple constants returns last constant" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("12 true false 4.5");
    try std.testing.expectEqual(Val.fromZig(f64, &vm, 4.5), actual);
}

test "can define" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const define_actual = try vm.evalStr("(def x 12)");
    try std.testing.expectEqual(Val.init(), define_actual);
    const get_actual = try vm.evalStr("x");
    try std.testing.expectEqual(Val.fromZig(i64, &vm, 12), get_actual);
}

test "can run lambda" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(
        Val.init(),
        try vm.evalStr("(def foo (lambda () (+ 1 2 3)))"),
    );
    try std.testing.expectEqual(
        Val.fromZig(i64, &vm, 6),
        try vm.evalStr("(foo)"),
    );
}

test "can define with defun" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(
        Val.init(),
        try vm.evalStr("(defun foo () (+ 1 2 3))"),
    );
    try std.testing.expectEqual(
        Val.fromZig(i64, &vm, 6),
        try vm.evalStr("(foo)"),
    );
}

fn add2Impl(vm: *Vm) Val.FunctionError!Val {
    const args = vm.localStack();
    if (args.len != 1) return Val.FunctionError.WrongArity;
    const arg = args[0].asInt();
    if (arg == null) return Val.FunctionError.WrongType;
    return Val.fromZig(i64, vm, 2 + arg.?);
}

const ADD_2_FN = Val.FunctionVal{
    .name = "add-2",
    .function = &add2Impl,
};

test "can eval custom fuction" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    try vm.global.registerFunction(&vm, &ADD_2_FN);
    defer vm.deinit();
    try std.testing.expectEqual(
        Val.fromZig(i64, &vm, 10),
        try vm.evalStr("(add-2 8)"),
    );
}
