const std = @import("std");

const ByteCodeFunction = @import("function.zig").ByteCodeFunction;
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const function = @import("function.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, "%define", defineFn);
    try vm.global.registerFunction(vm, "do", doFn);
    try vm.global.registerFunction(vm, "+", plusFn);
    try vm.global.registerFunction(vm, "-", minusFn);
    try vm.global.registerFunction(vm, "negate", negateFn);
    try vm.global.registerFunction(vm, "<", lessFn);
    try vm.global.registerFunction(vm, "str-len", strLenFn);
    try vm.global.registerFunction(vm, "str->sexps", strToSexpsFn);
    try vm.global.registerFunction(vm, "str->sexp", strToSexpFn);
    try vm.global.registerFunction(vm, "function-bytecode", functionBytecodeFn);
}

fn defineFn(vm: *Vm) function.Error!Val {
    const args = vm.stack.local();
    if (args.len != 2) {
        return function.Error.WrongArity;
    }
    const symbol = if (args[0].asInternedSymbol()) |s| s else return function.Error.WrongType;
    const value = args[1];
    try vm.global.registerValue(vm, symbol, value);
    return Val.init();
}

fn plusImpl(vm: *Vm, vals: []const Val) function.Error!Val {
    var int_sum: i64 = 0;
    var float_sum: f64 = 0.0;
    var has_float = false;
    for (vals) |v| {
        if (v.isInt()) {
            int_sum += try v.toZig(i64, vm);
        } else {
            has_float = true;
            float_sum += try v.toZig(f64, vm);
        }
    }
    if (has_float) {
        const int_sum_as_float: f64 = @floatFromInt(int_sum);
        return Val.fromZig(vm, float_sum + int_sum_as_float);
    }
    return Val.fromZig(vm, int_sum);
}

fn plusFn(vm: *Vm) function.Error!Val {
    return plusImpl(vm, vm.stack.local());
}

fn minusFn(vm: *Vm) function.Error!Val {
    const args = vm.stack.local();
    if (args.len == 0) return function.Error.WrongArity;
    if (args.len == 1) return negateImpl(vm, args[0]);
    const leading = args[0];
    const rest = try negateImpl(
        vm,
        try plusImpl(vm, args[1..]),
    );
    return plusImpl(vm, &.{ leading, rest });
}

fn negateImpl(vm: *Vm, val: Val) function.Error!Val {
    switch (val.repr) {
        .int => |x| return Val.fromZig(vm, -x),
        .float => |x| return Val.fromZig(vm, -x),
        else => return function.Error.WrongType,
    }
}

fn negateFn(vm: *Vm) function.Error!Val {
    const args = vm.stack.local();
    if (args.len != 1) return function.Error.WrongArity;
    return negateImpl(vm, args[0]);
}

fn lessFn(vm: *Vm) function.Error!Val {
    const args = vm.stack.local();
    const arg_count = args.len;
    if (arg_count == 0) return Val.fromZig(vm, true);
    if (arg_count == 1) if (args[0].isNumber()) return Val.fromZig(vm, true) else return function.Error.WrongType;
    var res = true;
    for (args[0 .. arg_count - 1], args[1..]) |val_a, val_b| {
        switch (val_a.repr) {
            .int => |a| switch (val_b.repr) {
                .int => |b| res = res and (a < b),
                .float => |b| {
                    const a_float: f64 = @floatFromInt(a);
                    res = res and (a_float < b);
                },
                else => return function.Error.WrongType,
            },
            .float => |a| {
                switch (val_b.repr) {
                    .int => |b| {
                        const b_float: f64 = @floatFromInt(b);
                        res = res and (a < b_float);
                    },
                    .float => |b| res = res and (a < b),
                    else => return function.Error.WrongType,
                }
            },
            else => return function.Error.WrongType,
        }
    }
    return Val.fromZig(vm, res);
}

pub fn doFn(vm: *Vm) function.Error!Val {
    const args = vm.stack.local();
    if (args.len == 0) return Val.init();
    return args[args.len - 1];
}

fn strLenFn(vm: *Vm) function.Error!Val {
    const args = vm.stack.local();
    if (args.len != 1) {
        return function.Error.WrongArity;
    }
    const str = try args[0].toZig([]const u8, vm);
    const len: i64 = @intCast(str.len);
    return Val.fromZig(vm, len);
}

fn strToSexpsFn(vm: *Vm) function.Error!Val {
    const args = vm.stack.local();
    if (args.len != 1) {
        return function.Error.WrongArity;
    }
    const str = try args[0].toZig([]const u8, vm);
    var ast_builder = @import("AstBuilder.zig").init(vm, str);
    while (try ast_builder.next()) |ast| {
        try vm.stack.push(ast.expr);
    }
    const exprs = vm.stack.local()[1..];
    return Val.fromZig(vm, exprs);
}

fn strToSexpFn(vm: *Vm) function.Error!Val {
    const sexps = try strToSexpsFn(vm);
    const exprs = try sexps.toZig([]const Val, vm);
    switch (exprs.len) {
        0 => return Val.init(),
        1 => return exprs[0],
        else => return function.Error.BadArg,
    }
}

fn functionBytecodeFn(vm: *Vm) function.Error!Val {
    const args = vm.stack.local();
    if (args.len != 1) return function.Error.WrongArity;
    const func = switch (args[0].repr) {
        .bytecode_function => |id| vm.objects.get(ByteCodeFunction, id).?,
        else => return function.Error.WrongType,
    };
    var ret = try vm.allocator().alloc(Val, func.instructions.len);
    defer vm.allocator().free(ret);
    for (0..func.instructions.len, func.instructions) |idx, instruction| {
        const code = switch (instruction) {
            .push => try Val.fromZig(vm, Symbol{ .quotes = 0, .name = "push" }),
            .eval => try Val.fromZig(vm, Symbol{ .quotes = 0, .name = "eval" }),
            .get_local => try Val.fromZig(vm, Symbol{ .quotes = 0, .name = "get_local" }),
            .deref => try Val.fromZig(vm, Symbol{ .quotes = 0, .name = "deref" }),
            .jump_if => try Val.fromZig(vm, Symbol{ .quotes = 0, .name = "jump_if" }),
            .jump => try Val.fromZig(vm, Symbol{ .quotes = 0, .name = "jump" }),
            .ret => try Val.fromZig(vm, Symbol{ .quotes = 0, .name = "ret" }),
        };
        const data: ?Val = switch (instruction) {
            .push => |v| v,
            .eval => |n| try Val.fromZig(vm, @as(i64, @intCast(n))),
            .get_local => |n| try Val.fromZig(vm, @as(i64, @intCast(n))),
            .deref => |sym| sym.toVal(),
            .jump_if => |n| try Val.fromZig(vm, @as(i64, n)),
            .jump => |n| try Val.fromZig(vm, @as(i64, n)),
            .ret => null,
        };
        ret[idx] = if (data) |d|
            try Val.fromZig(vm, @as([]const Val, &[_]Val{ code, d }))
        else
            try Val.fromZig(vm, @as([]const Val, &[_]Val{code}));
    }
    return try Val.fromZig(vm, ret);
}

test "str-len returns string length" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(
        4,
        try vm.evalStr(i64, "(str-len \"1234\")"),
    );
}

test "str->sexp produces s-expression" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr(Val, "(str->sexp \"   (+ 1 (foo 2 3 :key ''quoted))    \")");
    try std.testing.expectFmt(
        "(+ 1 (foo 2 3 :key ''quoted))",
        "{any}",
        .{actual.formatted(&vm)},
    );
}
