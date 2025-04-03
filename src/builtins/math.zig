const std = @import("std");

const Error = @import("../error.zig").Error;
const NativeFunction = @import("../NativeFunction.zig");
const Val = @import("../Val.zig");
const Vm = @import("../Vm.zig");
const converters = @import("../converters.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, NativeFunction.init("+", plusFn));
    try vm.global.registerFunction(vm, NativeFunction.init("-", minusFn));
    try vm.global.registerFunction(vm, NativeFunction.init("<", lessFn));
    try vm.global.registerFunction(vm, NativeFunction.init(">", greaterFn));
}

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
        return Val.from(vm, float_sum + int_sum_as_float);
    }
    return Val.from(vm, int_sum);
}

fn plusFn(vm: *Vm) Error!Val {
    return plusImpl(vm, vm.stack.local());
}

fn minusFn(vm: *Vm) Error!Val {
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
    const number = try val.to(Val.Number, vm);
    switch (number) {
        .int => |x| return Val.from(vm, -x),
        .float => |x| return Val.from(vm, -x),
    }
}

fn lessFn(vm: *Vm) Error!Val {
    const args = vm.stack.local();
    const arg_count = args.len;
    if (arg_count == 0) return Val.from(vm, true);
    if (arg_count == 1) if (args[0].is(Val.Number)) return Val.from(vm, true) else return Error.WrongType;
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
    return Val.from(vm, res);
}

fn greaterFn(vm: *Vm) Error!Val {
    const args = vm.stack.local();
    const arg_count = args.len;
    if (arg_count == 0) return Val.from(vm, true);
    if (arg_count == 1) if (args[0].is(Val.Number)) return Val.from(vm, true) else return Error.WrongType;
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
    return Val.from(vm, res);
}

test "+ adds integers" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(6, try vm.to(i64, try vm.evalStr("(+ 1 2 3)")));
}

test "+ adds floats" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(6.0, try vm.to(f64, try vm.evalStr("(+ 1.0 2.0 3.0)")));
}

test "+ adds mixed integers and floats and returns float" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(6.0, try vm.to(f64, try vm.evalStr("(+ 1 2.0 3)")));
    try std.testing.expectEqual(3.5, try vm.to(f64, try vm.evalStr("(+ 1.0 2 0.5)")));
}

test "+ returns 0 if no arguments" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(0, try vm.to(i64, try vm.evalStr("(+)")));
}

test "- subtracts integers" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(-4, try vm.to(i64, try vm.evalStr("(- 1 2 3)")));
}

test "- subtracts floats" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(-4.0, try vm.to(f64, try vm.evalStr("(- 1.0 2.0 3.0)")));
}

test "- subtracts mixed integers and floats and returns float" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(-4.0, try vm.to(f64, try vm.evalStr("(- 1 2.0 3)")));
}

test "- negates if only single argument" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(-1, try vm.to(i64, try vm.evalStr("(- 1)")));
    try std.testing.expectEqual(-1.0, try vm.to(f64, try vm.evalStr("(- 1.0)")));
}

test "- returns error if no arguments" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectError(
        Error.WrongArity,
        vm.evalStr("(-)"),
    );
}

test "< returns true if less, false otherwise" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(true, try vm.to(bool, try vm.evalStr("(< 1 2.2 3)")));
    try std.testing.expectEqual(true, try vm.to(bool, try vm.evalStr("(< 1)")));
    try std.testing.expectEqual(false, try vm.to(bool, try vm.evalStr("(< 1 2 3 2)")));
    try std.testing.expectEqual(false, try vm.to(bool, try vm.evalStr("(< 2 1)")));
    try std.testing.expectEqual(false, try vm.to(bool, try vm.evalStr("(< 1 1)")));
}

test "> returns true if greater, false otherwise" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(true, try vm.to(bool, try vm.evalStr("(> 2 1 0)")));
    try std.testing.expectEqual(false, try vm.to(bool, try vm.evalStr("(> 2 1 1.1)")));
    try std.testing.expectEqual(false, try vm.to(bool, try vm.evalStr("(> 1 1.5 1.8 2)")));
    try std.testing.expectEqual(false, try vm.to(bool, try vm.evalStr("(> 1 1)")));
    try std.testing.expectEqual(true, try vm.to(bool, try vm.evalStr("(> 2.0 1.0)")));
    try std.testing.expectEqual(false, try vm.to(bool, try vm.evalStr("(> 1.0 2.0)")));
    try std.testing.expectEqual(false, try vm.to(bool, try vm.evalStr("(> 1.0 1.0)")));
}
