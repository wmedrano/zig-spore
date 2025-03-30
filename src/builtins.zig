const std = @import("std");

const ByteCodeFunction = @import("ByteCodeFunction.zig");
const Error = @import("error.zig").Error;
const NativeFunction = @import("NativeFunction.zig");
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const converters = @import("converters.zig");
const math = @import("builtins/math.zig");
const string = @import("builtins/string.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("%define", defineFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("do", doFn));
    try vm.global.registerFunction(vm, NativeFunction.init("list", listFn));
    try vm.global.registerFunction(vm, NativeFunction.init("+", math.plusFn));
    try vm.global.registerFunction(vm, NativeFunction.init("-", math.minusFn));
    try vm.global.registerFunction(vm, NativeFunction.init("<", math.lessFn));
    try vm.global.registerFunction(vm, NativeFunction.init(">", math.greaterFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("str-len", string.strLenFn));
    try vm.global.registerFunction(vm, NativeFunction.init("str->sexps", string.strToSexpsFn));
    try vm.global.registerFunction(vm, NativeFunction.init("str->sexp", string.strToSexpFn));
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

pub fn doFn(_: *Vm, args: struct { rest: []const Val }) Error!Val {
    if (args.rest.len == 0) return Val.init();
    return args.rest[args.rest.len - 1];
}

fn listFn(vm: *Vm) Error!Val {
    const args = vm.stack.local();
    return Val.fromZig(vm, args);
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

test "do returns last expression" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(3, try vm.evalStr(i64, "(do 1 2 3)"));
}

test "do returns nil if no expressions" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr(Val, "(do)");
    try std.testing.expectEqual(Val.init(), actual);
}

test "list returns list of arguments" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr(Val, "(list 1 2 3)");
    const list = try actual.toZig([]const Val, &vm);
    try std.testing.expectEqual(@as(usize, 3), list.len);
    try std.testing.expectEqual(@as(i64, 1), try list[0].toZig(i64, &vm));
    try std.testing.expectEqual(@as(i64, 2), try list[1].toZig(i64, &vm));
    try std.testing.expectEqual(@as(i64, 3), try list[2].toZig(i64, &vm));
}
