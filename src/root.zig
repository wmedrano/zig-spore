//! Zig integration for the Spore scripting language.
//!
//! The bulk of the work is done by the `Vm` struct and functions like
//! `Vm.evalStr` and `Vm.runGc`.
const std = @import("std");
pub const Vm = @import("Vm.zig");

const ByteCodeFunction = Val.ByteCodeFunction;
const NativeFunction = Val.NativeFunction;
const Symbol = Val.Symbol;

pub const Error = @import("error.zig").Error;
pub const Val = Vm.Val;

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
    const actual = try vm.to(i64, try vm.evalStr("12"));
    try std.testing.expectEqual(12, actual);
}

test "eval can return symbol" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("'+");
    try std.testing.expectEqual(
        try Val.from(&vm, try Symbol.fromStr("+")),
        actual,
    );
}

test "eval multiple constants returns last constant" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.to(f64, try vm.evalStr("12 true false 4.5"));
    try std.testing.expectEqual(4.5, actual);
}

test "can define" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    _ = try vm.evalStr("(def x 12)");
    try std.testing.expectEqual(
        12,
        try vm.to(i64, try vm.evalStr("x")),
    );
}

test "can evaluate if" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(4, try vm.to(i64, try vm.evalStr("(if true (do 1 2 3 4) (do 5 6))")));
    try std.testing.expectEqual(4, try vm.to(i64, try vm.evalStr("(if true (do 1 2 3 4))")));
    try std.testing.expectEqual(6, try vm.to(i64, try vm.evalStr("(if false (do 1 2 3 4) (do 5 6))")));
    try vm.to(void, try vm.evalStr("(if false (do 1 2 3 4))"));
}

test "can evaluate when" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(4, try vm.to(i64, try vm.evalStr("(when true 1 2 3 4)")));
    try vm.to(void, try vm.evalStr("(when false 1 2 3 4)"));
}

test "can run function" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    _ = try vm.evalStr("(def foo (function () (+ 1 2 3)))");
    try std.testing.expectEqual(
        6,
        try vm.to(i64, try vm.evalStr("(foo)")),
    );
}

test "can define with defun" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    _ = try vm.evalStr("(defun foo (a b c) (+ a b c))");
    try std.testing.expectEqual(
        6,
        try vm.to(i64, try vm.evalStr("(foo 1 2 3)")),
    );
}

test "function call with wrong args returns error" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    _ = try vm.evalStr("(defun foo (a b c) (+ a b c))");
    try std.testing.expectError(error.WrongArity, vm.evalStr("(foo 1 2)"));
}

test "can eval recursive function" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    _ = try vm.evalStr(
        \\ (defun fib (n)
        \\   (if (< n 2) (return n))
        \\   (+ (fib (- n 1))
        \\      (fib (- n 2))))
    );
    try std.testing.expectEqual(
        55,
        try vm.to(i64, try vm.evalStr("(fib 10)")),
    );
}

fn addTwoFn(vm: *Vm, args: struct { num: i64 }) Error!Val {
    return Val.from(vm, 2 + args.num);
}

test "can eval custom fuction" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.global.registerFunction(
        &vm,
        NativeFunction.withArgParser(.{ .name = "add-2" }, addTwoFn),
    );
    try std.testing.expectEqual(
        10,
        try vm.to(i64, try vm.evalStr("(add-2 8)")),
    );
}
