const std = @import("std");

const ByteCodeFunction = @import("../ByteCodeFunction.zig");
const Error = @import("../error.zig").Error;
const NativeFunction = Val.NativeFunction;
const SexpBuilder = @import("../compiler/SexpBuilder.zig");
const Symbol = @import("../Symbol.zig");
const Val = Vm.Val;
const Vm = @import("../Vm.zig");
const converters = @import("../converters.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, NativeFunction.withArgParser(.{ .name = "str->sexps" }, strToSexpsFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser(.{ .name = "str->sexp" }, strToSexpFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser(.{ .name = "function-bytecode" }, functionBytecodeFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser(.{ .name = "apply" }, applyFn));
}

fn strToSexpsFn(vm: *Vm, args: struct { str: []const u8 }) Error!Val {
    var sexp_builder = SexpBuilder.init(args.str);
    const sexps = try sexp_builder.parseAll(vm, vm.allocator());
    return Val.fromOwnedList(vm, sexps);
}

fn strToSexpFn(vm: *Vm, args: struct { str: []const u8 }) Error!Val {
    var sexp_builder = SexpBuilder.init(args.str);
    const sexp = if (try sexp_builder.next(vm)) |expr| expr else return Val.init();
    if (try sexp_builder.next(vm)) |_| return Error.BadArg;
    return sexp;
}

test "str->sexp produces s-expression" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("(str->sexp \"   (+ 1 (foo 2 3 :key ''quoted))    \")");
    try std.testing.expectFmt(
        "(+ 1 (foo 2 3 :key ''quoted))",
        "{any}",
        .{actual.formatted(&vm)},
    );
}

test "str->sexp on empty string produces void" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.to(void, try vm.evalStr("(str->sexp \"\")"));
}

test "str->sexp with multiple sexps returns error" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectError(
        Error.BadArg,
        vm.evalStr("(str->sexp \"(+ 1 2) (+ 3 4)\")"),
    );
}

fn functionBytecodeFn(vm: *Vm, args: struct { func: Val }) Error!Val {
    const func = try args.func.to(ByteCodeFunction, vm);
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
            .push => try Val.from(vm, symbols.push),
            .eval => try Val.from(vm, symbols.eval),
            .get_local => try Val.from(vm, symbols.@"get-local"),
            .deref => try Val.from(vm, symbols.deref),
            .jump_if => try Val.from(vm, symbols.@"jump-if"),
            .jump => try Val.from(vm, symbols.jump),
            .ret => try Val.from(vm, symbols.ret),
        };
        const data: ?Val = switch (instruction) {
            .push => |v| v,
            .eval => |n| try Val.from(vm, @as(i64, @intCast(n))),
            .get_local => |n| try Val.from(vm, @as(i64, @intCast(n))),
            .deref => |sym| sym.toVal(),
            .jump_if => |n| try Val.from(vm, @as(i64, n)),
            .jump => |n| try Val.from(vm, @as(i64, n)),
            .ret => null,
        };
        ret[idx] = if (data) |d|
            try Val.from(vm, @as([]const Val, &[_]Val{ code, d }))
        else
            try Val.from(vm, @as([]const Val, &[_]Val{code}));
    }
    return try Val.from(vm, ret);
}

fn applyFn(vm: *Vm, args: struct { func: Val, args: []const Val }) Error!Val {
    if (args.func.is(ByteCodeFunction)) {
        const func = try args.func.to(ByteCodeFunction, vm);
        return func.executeWith(vm, args.args);
    }
    const func = try args.func.to(*const NativeFunction, vm);
    return func.executeWith(vm, args.args);
}

test "function-bytecode returns bytecode representation" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    _ = try vm.evalStr("(defun foo (x) (if x (return 1)) (bar))");
    const actual = try vm.evalStr("(function-bytecode foo)");
    try std.testing.expect(actual.is([]const Val));
    try std.testing.expectFmt(
        "((get-local 0) (jump-if 2) (push (<void>)) (jump 2) (push 1) (ret) (deref bar) (eval 1))",
        "{any}",
        .{actual.formatted(&vm)},
    );
}

test "apply can execute native functions" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(6, try vm.to(i64, try vm.evalStr("(apply + (list 1 2 3))")));
    try std.testing.expectEqual(16, try vm.to(i64, try vm.evalStr("(+ 10 (apply + (list 1 2 3)))")));
}

test "apply can execute bytecode functions" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    _ = try vm.evalStr("(defun sum (x y z) (+ x y z))");
    try std.testing.expectEqual(6, try vm.to(i64, try vm.evalStr("(apply sum (list 1 2 3))")));
    try std.testing.expectEqual(16, try vm.to(i64, try vm.evalStr("(+ 10 (apply sum (list 1 2 3)))")));
}

test "apply can execute functions with no arguments" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    // Native function.
    try std.testing.expectEqual(0, try vm.to(i64, try vm.evalStr("(apply + (list))")));

    // Bytecode function.
    _ = try vm.evalStr("(defun five () 5)");
    try std.testing.expectEqual(5, try vm.to(i64, try vm.evalStr("(apply five (list))")));
}

test "apply fails if not a function" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectError(
        Error.WrongType,
        vm.evalStr("(apply 1 (list 1 2 3))"),
    );
}
