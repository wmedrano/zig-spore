const std = @import("std");

const Vm = @import("../Vm.zig");
const Val = @import("../Val.zig");
const Error = @import("../error.zig").Error;
const converters = @import("../converters.zig");

fn plusImpl(vm: *Vm, vals: []const Val) Error!Val {
    var int_sum: i64 = 0;
    var float_sum: f64 = 0.0;
    var has_float = false;
    var numbersIter = converters.iter(Val.Number, vm, vals);
    while (try numbersIter.next()) |v| switch (v) {
        .int => |x| int_sum += x,
        .float => |x| {
            has_float = true;
            float_sum += x;
        },
    };
    if (has_float) {
        const int_sum_as_float: f64 = @floatFromInt(int_sum);
        return Val.fromZig(vm, float_sum + int_sum_as_float);
    }
    return Val.fromZig(vm, int_sum);
}

pub fn plusFn(vm: *Vm) Error!Val {
    return plusImpl(vm, vm.stack.local());
}

pub fn minusFn(vm: *Vm) Error!Val {
    const args = vm.stack.local();
    if (args.len == 0) return Error.WrongArity;
    if (args.len == 1) return negate(vm, args[0]);
    const leading = args[0];
    const rest = try negate(
        vm,
        try plusImpl(vm, args[1..]),
    );
    return plusImpl(vm, &.{ leading, rest });
}

fn negate(vm: *Vm, val: Val) Error!Val {
    const number = try val.toZig(Val.Number, vm);
    switch (number) {
        .int => |x| return Val.fromZig(vm, -x),
        .float => |x| return Val.fromZig(vm, -x),
    }
}

pub fn lessFn(vm: *Vm) Error!Val {
    const args = vm.stack.local();
    const arg_count = args.len;
    if (arg_count == 0) return Val.fromZig(vm, true);
    if (arg_count == 1) if (args[0].is(Val.Number)) return Val.fromZig(vm, true) else return Error.WrongType;
    var res = true;
    var lhs = converters.iter(Val.Number, vm, args[0 .. arg_count - 1]);
    var rhs = converters.iter(Val.Number, vm, args[1..]);
    while (try lhs.next()) |val_a| {
        const val_b = (try rhs.next()).?;
        switch (val_a) {
            .int => |a| switch (val_b) {
                .int => |b| res = res and (a < b),
                .float => |b| {
                    const a_float: f64 = @floatFromInt(a);
                    res = res and (a_float < b);
                },
            },
            .float => |a| {
                switch (val_b) {
                    .int => |b| {
                        const b_float: f64 = @floatFromInt(b);
                        res = res and (a < b_float);
                    },
                    .float => |b| res = res and (a < b),
                }
            },
        }
    }
    return Val.fromZig(vm, res);
}

pub fn greaterFn(vm: *Vm) Error!Val {
    const args = vm.stack.local();
    const arg_count = args.len;
    if (arg_count == 0) return Val.fromZig(vm, true);
    if (arg_count == 1) if (args[0].is(Val.Number)) return Val.fromZig(vm, true) else return Error.WrongType;
    var res = true;
    var lhs = converters.iter(Val.Number, vm, args[0 .. arg_count - 1]);
    var rhs = converters.iter(Val.Number, vm, args[1..]);
    while (try lhs.next()) |val_a| {
        const val_b = (try rhs.next()).?;
        switch (val_a) {
            .int => |a| switch (val_b) {
                .int => |b| res = res and (a > b),
                .float => |b| {
                    const a_float: f64 = @floatFromInt(a);
                    res = res and (a_float > b);
                },
            },
            .float => |a| {
                switch (val_b) {
                    .int => |b| {
                        const b_float: f64 = @floatFromInt(b);
                        res = res and (a > b_float);
                    },
                    .float => |b| res = res and (a > b),
                }
            },
        }
    }
    return Val.fromZig(vm, res);
}

test "+ adds integers" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(6, try vm.evalStr(i64, "(+ 1 2 3)"));
}

test "+ adds floats" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(6.0, try vm.evalStr(f64, "(+ 1.0 2.0 3.0)"));
}

test "+ adds mixed integers and floats and returns float" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(6.0, try vm.evalStr(f64, "(+ 1 2.0 3)"));
    try std.testing.expectEqual(3.5, try vm.evalStr(f64, "(+ 1.0 2 0.5)"));
}

test "+ returns 0 if no arguments" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(0, try vm.evalStr(i64, "(+)"));
}

test "- subtracts integers" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(-4, try vm.evalStr(i64, "(- 1 2 3)"));
}

test "- subtracts floats" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(-4.0, try vm.evalStr(f64, "(- 1.0 2.0 3.0)"));
}

test "- subtracts mixed integers and floats and returns float" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(-4.0, try vm.evalStr(f64, "(- 1 2.0 3)"));
}

test "- negates if only single argument" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(-1, try vm.evalStr(i64, "(- 1)"));
    try std.testing.expectEqual(-1.0, try vm.evalStr(f64, "(- 1.0)"));
}

test "- returns error if no arguments" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectError(
        Error.WrongArity,
        vm.evalStr(Val, "(-)"),
    );
}
