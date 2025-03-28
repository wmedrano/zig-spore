const std = @import("std");

const Allocator = std.mem.Allocator;
const Instruction = @import("instruction.zig").Instruction;
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const function = @import("function.zig");

pub const DefMacro = struct {
    pub const name = "%def-macro";

    pub fn fnImpl(vm: *Vm) function.Error!Val {
        const internal_define_symbol = try (Symbol{ .quotes = 0, .name = "%define" }).intern(vm);
        const expr = vm.stack.local();
        if (expr.len != 2) {
            return function.Error.BadDefine;
        }
        const symbol = if (expr[0].asInternedSymbol()) |x| x.quoted() else return function.Error.ExpectedIdentifier;
        return try Val.fromZig([]const Val, vm, &.{
            internal_define_symbol.toVal(),
            symbol.toVal(),
            expr[1],
        });
    }
};

pub const DefunMacro = struct {
    pub const name = "%defun-macro";

    pub fn fnImpl(vm: *Vm) function.Error!Val {
        const internal_define_symbol = try (Symbol{ .quotes = 0, .name = "%define" }).intern(vm);
        const function_symbol = try (Symbol{ .quotes = 0, .name = "function" }).intern(vm);
        const expr = vm.stack.local();
        if (expr.len < 3) {
            return function.Error.BadDefine;
        }
        const function_name = if (expr[0].asInternedSymbol()) |s| s else return function.Error.BadDefine;
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
        return try Val.fromZig(
            []const Val,
            vm,
            &.{
                internal_define_symbol.toVal(),
                function_name.quoted().toVal(),
                function_expr_val,
            },
        );
    }
};

pub const WhenMacro = struct {
    pub const name = "%when-macro";

    pub fn fnImpl(vm: *Vm) function.Error!Val {
        const if_symbol = try (Symbol{ .quotes = 0, .name = "if" }).intern(vm);
        const do_symbol = try (Symbol{ .quotes = 0, .name = "do" }).intern(vm);
        const expr = vm.stack.local();
        if (expr.len < 2) {
            return function.Error.BadWhen;
        }
        var body_expr = try vm.allocator().dupe(Val, expr);
        defer vm.allocator().free(body_expr);
        const pred = body_expr[0];
        body_expr[0] = do_symbol.toVal();
        return try Val.fromZig([]const Val, vm, &.{
            if_symbol.toVal(),
            pred,
            try Val.fromZig([]const Val, vm, body_expr),
        });
    }
};

pub const SubtractMacro = struct {
    pub const name = "%subtract-macro";

    pub fn fnImpl(vm: *Vm) function.Error!Val {
        const args = vm.stack.local();
        if (args.len == 0) {
            return function.Error.WrongArity;
        }
        const negate_symbol = try (Symbol{ .quotes = 0, .name = "negate" }).intern(vm);
        if (args.len == 1) {
            return Val.fromZig([]const Val, vm, &.{
                negate_symbol.toVal(),
                args[0],
            });
        }
        const plus_symbol = try (Symbol{ .quotes = 0, .name = "+" }).intern(vm);
        var negative_builder = try vm.allocator().dupe(Val, args);
        defer vm.allocator().free(negative_builder);
        negative_builder[0] = negate_symbol.toVal();
        const negative_part = try Val.fromZig([]const Val, vm, negative_builder);
        return Val.fromZig(
            []const Val,
            vm,
            &.{ plus_symbol.toVal(), args[0], negative_part },
        );
    }
};
