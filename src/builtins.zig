const std = @import("std");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const function = @import("function.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, DefineFn);
    try vm.global.registerFunction(vm, DoFn);
    try vm.global.registerFunction(vm, PlusFn);
    try vm.global.registerFunction(vm, StrLenFn);
    try vm.global.registerFunction(vm, StrToSexpsFn);
    try vm.global.registerFunction(vm, StrToSexpFn);
}

const DefineFn = struct {
    pub const name = "%define";

    pub fn fnImpl(vm: *Vm) function.Error!Val {
        const args = vm.localStack();
        if (args.len != 2) {
            return function.Error.WrongArity;
        }
        const symbol = if (args[0].asInternedSymbol()) |s| s else return function.Error.WrongType;
        const value = args[1];
        try vm.global.registerValue(vm, symbol, value);
        return Val.init();
    }
};

const PlusFn = struct {
    pub const name = "+";

    pub fn fnImpl(vm: *Vm) function.Error!Val {
        var int_sum: i64 = 0;
        var float_sum: f64 = 0.0;
        var has_float = false;
        for (vm.localStack()) |v| {
            if (v.isInt()) {
                int_sum += try v.toZig(i64, vm);
            } else {
                has_float = true;
                float_sum += try v.toZig(f64, vm);
            }
        }
        if (has_float) {
            const int_sum_as_float: f64 = @floatFromInt(int_sum);
            return Val.fromZig(f64, vm, float_sum + int_sum_as_float);
        }
        return Val.fromZig(i64, vm, int_sum);
    }
};

const DoFn = struct {
    pub const name = "do";

    pub fn fnImpl(vm: *Vm) function.Error!Val {
        const args = vm.localStack();
        if (args.len == 0) return Val.init();
        return args[args.len - 1];
    }
};

const StrLenFn = struct {
    pub const name = "str-len";
    pub fn fnImpl(vm: *Vm) function.Error!Val {
        const args = vm.localStack();
        if (args.len != 1) {
            return function.Error.WrongArity;
        }
        const str = try args[0].toZig([]const u8, vm);
        return Val.fromZig(i64, vm, @intCast(str.len));
    }
};

pub const StrToSexpsFn = struct {
    pub const name = "str->sexps";
    pub fn fnImpl(vm: *Vm) function.Error!Val {
        const args = vm.localStack();
        if (args.len != 1) {
            return function.Error.WrongArity;
        }
        const str = try args[0].toZig([]const u8, vm);
        var ast_builder = @import("AstBuilder.zig").init(vm, str);
        while (try ast_builder.next()) |ast| {
            try vm.pushStackVals(&.{ast.expr});
        }
        const exprs = vm.localStack()[1..];
        return Val.fromZig([]const Val, vm, exprs);
    }
};

pub const StrToSexpFn = struct {
    pub const name = "str->sexp";
    pub fn fnImpl(vm: *Vm) function.Error!Val {
        const exprs = try (try StrToSexpsFn.fnImpl(vm)).toZig([]const Val, vm);
        switch (exprs.len) {
            0 => return Val.init(),
            1 => return exprs[0],
            else => return function.Error.BadArg,
        }
    }
};

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
    try std.testing.expectFmt(
        "(+ 1 (foo 2 3 :key ''quoted))",
        "{any}",
        .{(try vm.evalStr(Val, "(str->sexp \"   (+ 1 (foo 2 3 :key ''quoted))    \")")).formatted(&vm)},
    );
}
