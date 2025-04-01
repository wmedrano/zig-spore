const std = @import("std");

const AstBuilder = @import("../compiler/AstBuilder.zig");
const Error = @import("../error.zig").Error;
const NativeFunction = Val.NativeFunction;
const Val = Vm.Val;
const Vm = @import("../Vm.zig");
const converters = @import("../converters.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("str-len", strLenFn));
    try vm.global.registerFunction(vm, NativeFunction.init("str->sexps", strToSexpsFn));
    try vm.global.registerFunction(vm, NativeFunction.init("str->sexp", strToSexpFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("print", printFn));
}

pub fn strLenFn(vm: *Vm, args: struct { str: []const u8 }) Error!Val {
    const len: i64 = @intCast(args.str.len);
    return Val.fromZig(vm, len);
}

pub fn strToSexpsFn(vm: *Vm) Error!Val {
    const args = try converters.parseAsArgs(
        struct { str: []const u8 },
        vm,
        vm.stack.local(),
    );
    var ast_builder = AstBuilder.init(vm, args.str);
    while (try ast_builder.next()) |ast| {
        try vm.stack.push(ast.expr);
    }
    const exprs = vm.stack.local()[1..];
    return Val.fromZig(vm, exprs);
}

pub fn strToSexpFn(vm: *Vm) Error!Val {
    const sexps = try strToSexpsFn(vm);
    const exprs = try sexps.toZig([]const Val, vm);
    switch (exprs.len) {
        0 => return Val.init(),
        1 => return exprs[0],
        else => return Error.BadArg,
    }
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

test "str->sexp on empty string produces void" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.evalStr(void, "(str->sexp \"\")");
}

test "str->sexp with multiple sexps returns error" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectError(
        Error.BadArg,
        vm.evalStr(Val, "(str->sexp \"(+ 1 2) (+ 3 4)\")"),
    );
}

fn printFn(vm: *Vm, args: struct { val: Val }) Error!Val {
    if (args.val.is([]const u8)) {
        const str = try args.val.toZig([]const u8, vm);
        std.debug.print("{s}\n", .{str});
    } else {
        const formatted = args.val.formatted(vm);
        std.debug.print("{any}\n", .{formatted});
    }
    return Val.init();
}
