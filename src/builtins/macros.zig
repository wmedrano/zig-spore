const std = @import("std");
const root = @import("../root.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const Instruction = @import("../instruction.zig").Instruction;
const Symbol = Val.Symbol;
const Val = Vm.Val;
const Vm = root.Vm;
const NativeFunction = Val.NativeFunction;
const converters = @import("../converters.zig");

pub fn registerAll(vm: *Vm) Error!void {
    try vm.global.registerFunction(vm, NativeFunction.init(.{ .name = "def", .is_macro = true }, defMacro));
    try vm.global.registerFunction(vm, NativeFunction.init(.{ .name = "defun", .is_macro = true }, defunMacro));
    try vm.global.registerFunction(vm, NativeFunction.init(.{ .name = "when", .is_macro = true }, whenMacro));
}

fn defMacro(vm: *Vm) Error!Val {
    const expr = vm.stack.local();
    if (expr.len != 2) {
        return Error.BadDefine;
    }
    const symbol = expr[0].to(Symbol.Interned, {}) catch return Error.ExpectedIdentifier;
    return try Val.from(vm, @as([]const Val, &[_]Val{
        try Val.from(vm, try Symbol.fromStr("%define")),
        symbol.quoted().toVal(),
        expr[1],
    }));
}

fn defunMacro(vm: *Vm) Error!Val {
    const function_symbol = try (try Symbol.fromStr("function")).intern(vm);
    const expr = vm.stack.local();
    if (expr.len < 3) {
        return Error.BadDefine;
    }
    const function_name = expr[0].to(Symbol.Interned, {}) catch return Error.BadDefine;
    const args = expr[1];
    const body = expr[2..];
    var function_expr = try std.ArrayListUnmanaged(Val).initCapacity(
        vm.allocator(),
        2 + body.len,
    );
    defer function_expr.deinit(vm.allocator());
    function_expr.appendAssumeCapacity(function_symbol.toVal());
    function_expr.appendAssumeCapacity(args);
    function_expr.appendSliceAssumeCapacity(body);
    const function_expr_val = try Val.fromOwnedList(
        vm,
        try function_expr.toOwnedSlice(vm.allocator()),
    );
    return try Val.from(
        vm,
        @as([]const Val, &[_]Val{
            try Val.from(vm, try Symbol.fromStr("%define")),
            function_name.quoted().toVal(),
            function_expr_val,
        }),
    );
}

fn whenMacro(vm: *Vm) Error!Val {
    const if_symbol = try (try Symbol.fromStr("if")).intern(vm);
    const do_symbol = try (try Symbol.fromStr("do")).intern(vm);
    const expr = vm.stack.local();
    if (expr.len < 2) {
        return Error.BadWhen;
    }
    var body_expr = try vm.allocator().dupe(Val, expr);
    defer vm.allocator().free(body_expr);
    const pred = body_expr[0];
    body_expr[0] = do_symbol.toVal();
    return try Val.from(vm, @as([]const Val, &.{
        if_symbol.toVal(),
        pred,
        try Val.from(vm, body_expr),
    }));
}
