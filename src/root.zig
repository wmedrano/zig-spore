pub const Vm = @import("Vm.zig");
pub const Val = @import("val.zig").Val;

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
    try std.testing.expectEqual(Val{ .int = 12 }, actual);
}

test "eval can return symbol" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("'+");
    try std.testing.expectEqual((try vm.newSymbol("+")).toVal(), actual);
}

test "eval multiple constants returns last constant" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("12 true false 4.5");
    try std.testing.expectEqual(Val{ .float = 4.5 }, actual);
}

test "can define" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const define_actual = try vm.evalStr("(def x 12)");
    try std.testing.expectEqual(Val{ .void = {} }, define_actual);
    const get_actual = try vm.evalStr("x");
    try std.testing.expectEqual(Val{ .int = 12 }, get_actual);
}

test "can run lambda" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(
        Val{ .void = {} },
        try vm.evalStr("(def foo (lambda () (+ 1 2 3)))"),
    );
    try std.testing.expectEqual(
        Val{ .int = 6 },
        try vm.evalStr("(foo)"),
    );
}

test "can define with defun" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(
        Val{ .void = {} },
        try vm.evalStr("(defun foo () (+ 1 2 3))"),
    );
    try std.testing.expectEqual(
        Val{ .int = 6 },
        try vm.evalStr("(foo)"),
    );
}
