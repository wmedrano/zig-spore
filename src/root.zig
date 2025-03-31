//! Zig integration for the Spore scripting language.
//!
//! The bulk of the work is done by the `Vm` struct.
const std = @import("std");

const ByteCodeFunction = @import("ByteCodeFunction.zig");
const NativeFunction = @import("NativeFunction.zig");
const Symbol = @import("Symbol.zig");

pub const Error = @import("error.zig").Error;
pub const Module = @import("Module.zig");
pub const Val = @import("Val.zig");
pub const Vm = @import("Vm.zig");

test "can make vm" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
}

test "can run gc" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    try vm.runGc(&.{});
    defer vm.deinit();
}

test "eval constant returns constant" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr(i64, "12");
    try std.testing.expectEqual(12, actual);
}

test "eval can return symbol" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr(Val, "'+");
    try std.testing.expectEqual(
        try Val.fromZig(&vm, try Symbol.fromStr("+")),
        actual,
    );
}

test "eval multiple constants returns last constant" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr(f64, "12 true false 4.5");
    try std.testing.expectEqual(4.5, actual);
}

test "can define" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.evalStr(void, "(def x 12)");
    try std.testing.expectEqual(
        12,
        try vm.evalStr(i64, "x"),
    );
}

test "can evaluate if" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(4, try vm.evalStr(i64, "(if true (do 1 2 3 4) (do 5 6))"));
    try std.testing.expectEqual(4, try vm.evalStr(i64, "(if true (do 1 2 3 4))"));
    try std.testing.expectEqual(6, try vm.evalStr(i64, "(if false (do 1 2 3 4) (do 5 6))"));
    try vm.evalStr(void, "(if false (do 1 2 3 4))");
}

test "can evaluate when" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(4, try vm.evalStr(i64, "(when true 1 2 3 4)"));
    try vm.evalStr(void, "(when false 1 2 3 4)");
}

test "can run function" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.evalStr(void, "(def foo (function () (+ 1 2 3)))");
    try std.testing.expectEqual(
        6,
        try vm.evalStr(i64, "(foo)"),
    );
}

test "can define with defun" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.evalStr(void, "(defun foo (a b c) (+ a b c))");
    try std.testing.expectEqual(
        6,
        try vm.evalStr(i64, "(foo 1 2 3)"),
    );
}

test "function call with wrong args returns error" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.evalStr(void, "(defun foo (a b c) (+ a b c))");
    try std.testing.expectError(error.WrongArity, vm.evalStr(i64, "(foo 1 2)"));
}

test "can eval recursive function" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.evalStr(void, "(defun fib (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))");
    try std.testing.expectEqual(
        55,
        try vm.evalStr(i64, "(fib 10)"),
    );
}

fn addTwoFn(vm: *Vm, args: struct { num: i64 }) Error!Val {
    return Val.fromZig(vm, 2 + args.num);
}

test "can eval custom fuction" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.global.registerFunction(
        &vm,
        NativeFunction.withArgParser("add-2", addTwoFn),
    );
    try std.testing.expectEqual(
        10,
        try vm.evalStr(i64, "(add-2 8)"),
    );
}
