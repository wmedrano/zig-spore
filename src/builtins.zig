const std = @import("std");

const ByteCodeFunction = @import("ByteCodeFunction.zig");
const Error = @import("error.zig").Error;
const NativeFunction = @import("NativeFunction.zig");
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const converters = @import("converters.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("%define", defineFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("do", doFn));
    try vm.global.registerFunction(vm, NativeFunction.init("+", plusFn));
    try vm.global.registerFunction(vm, NativeFunction.init("-", minusFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("negate", negateFn));
    try vm.global.registerFunction(vm, NativeFunction.init("<", lessFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("str-len", strLenFn));
    try vm.global.registerFunction(vm, NativeFunction.init("str->sexps", strToSexpsFn));
    try vm.global.registerFunction(vm, NativeFunction.init("str->sexp", strToSexpFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("function-bytecode", functionBytecodeFn));
}

fn defineFn(vm: *Vm, args: struct { symbol: Symbol.Interned, value: Val }) Error!Val {
    try vm.global.registerValue(
        vm,
        args.symbol,
        args.value,
    );
    return Val.init();
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
        return Val.fromZig(vm, float_sum + int_sum_as_float);
    }
    return Val.fromZig(vm, int_sum);
}

fn plusFn(vm: *Vm) Error!Val {
    return plusImpl(vm, vm.stack.local());
}

fn minusFn(vm: *Vm) Error!Val {
    const args = vm.stack.local();
    if (args.len == 0) return Error.WrongArity;
    if (args.len == 1) return negateImpl(vm, args[0]);
    const leading = args[0];
    const rest = try negateImpl(
        vm,
        try plusImpl(vm, args[1..]),
    );
    return plusImpl(vm, &.{ leading, rest });
}

fn negateImpl(vm: *Vm, val: Val) Error!Val {
    const number = try val.toZig(Val.Number, vm);
    switch (number) {
        .int => |x| return Val.fromZig(vm, -x),
        .float => |x| return Val.fromZig(vm, -x),
    }
}

fn negateFn(vm: *Vm, args: struct { v: Val }) Error!Val {
    return negateImpl(vm, args.v);
}

fn lessFn(vm: *Vm) Error!Val {
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

pub fn doFn(_: *Vm, args: struct { rest: []const Val }) Error!Val {
    if (args.rest.len == 0) return Val.init();
    return args.rest[args.rest.len - 1];
}

fn strLenFn(vm: *Vm, args: struct { str: []const u8 }) Error!Val {
    const len: i64 = @intCast(args.str.len);
    return Val.fromZig(vm, len);
}

fn strToSexpsFn(vm: *Vm) Error!Val {
    const args = try converters.parseAsArgs(
        struct { str: []const u8 },
        vm,
        vm.stack.local(),
    );
    var ast_builder = @import("AstBuilder.zig").init(vm, args.str);
    while (try ast_builder.next()) |ast| {
        try vm.stack.push(ast.expr);
    }
    const exprs = vm.stack.local()[1..];
    return Val.fromZig(vm, exprs);
}

fn strToSexpFn(vm: *Vm) Error!Val {
    const sexps = try strToSexpsFn(vm);
    const exprs = try sexps.toZig([]const Val, vm);
    switch (exprs.len) {
        0 => return Val.init(),
        1 => return exprs[0],
        else => return Error.BadArg,
    }
}

fn functionBytecodeFn(vm: *Vm, args: struct { func: Val }) Error!Val {
    const func = try args.func.toZig(ByteCodeFunction, vm);
    var ret = try vm.allocator().alloc(Val, func.instructions.len);
    defer vm.allocator().free(ret);
    const symbols = try converters.symbolTable(vm, struct {
        push: Symbol.Interned,
        eval: Symbol.Interned,
        @"get-local": Symbol.Interned,
        deref: Symbol.Interned,
        @"jump-if": Symbol.Interned,
        jump: Symbol.Interned,
        ret: Symbol.Interned,
    });
    for (0..func.instructions.len, func.instructions) |idx, instruction| {
        const code = switch (instruction) {
            .push => try Val.fromZig(vm, symbols.push),
            .eval => try Val.fromZig(vm, symbols.eval),
            .get_local => try Val.fromZig(vm, symbols.@"get-local"),
            .deref => try Val.fromZig(vm, symbols.deref),
            .jump_if => try Val.fromZig(vm, symbols.@"jump-if"),
            .jump => try Val.fromZig(vm, symbols.jump),
            .ret => try Val.fromZig(vm, symbols.ret),
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
