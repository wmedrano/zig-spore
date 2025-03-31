const std = @import("std");

const Error = @import("error.zig").Error;
const NativeFunction = @import("NativeFunction.zig");
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const builtin_macros = @import("builtin_macros.zig");
const converters = @import("converters.zig");

const MacroExpander = @This();

@"%define": Symbol.Interned,
def: Symbol.Interned,
defun: Symbol.Interned,
function: Symbol.Interned,
do: Symbol.Interned,
@"if": Symbol.Interned,
when: Symbol.Interned,
@"return": Symbol.Interned,

/// Creates a new macro expander.
pub fn init(vm: *Vm) !MacroExpander {
    return try converters.symbolTable(vm, MacroExpander);
}

/// Expands all the macros in ast.
pub fn macroExpand(self: MacroExpander, vm: *Vm, expr: Val) Error!Val {
    if (try self.maybeMacroExpand(vm, expr)) |v| return v else return expr;
}

/// Similar to `macroExpand` but returns `null` if no macro expansions were performed.
fn maybeMacroExpand(self: MacroExpander, vm: *Vm, expr: Val) !?Val {
    const subexpressions = expr.toZig([]const Val, vm) catch return null;
    if (subexpressions.len == 0) return null;
    const leading_val = if (subexpressions.len == 0) return null else subexpressions[0];
    const leading_symbol = leading_val.toZig(Symbol.Interned, {}) catch return null;
    const macro_fn: ?*const NativeFunction = if (leading_symbol.eql(self.def))
        NativeFunction.init("def", builtin_macros.defMacro)
    else if (leading_symbol.eql(self.defun))
        NativeFunction.init("defun", builtin_macros.defunMacro)
    else if (leading_symbol.eql(self.when))
        NativeFunction.init("when", builtin_macros.whenMacro)
    else
        null;
    if (macro_fn) |f| {
        const expanded = try f.executeWith(vm, subexpressions[1..]);
        return try self.macroExpand(vm, expanded);
    }
    var maybe_expanded_subexpressions: ?[]Val = try self.maybeMacroExpandSubexpressions(vm, subexpressions);
    defer if (maybe_expanded_subexpressions) |vals| vm.allocator().free(vals);
    if (maybe_expanded_subexpressions) |expanded_subexpressions| {
        const ret = try Val.fromOwnedList(vm, expanded_subexpressions);
        maybe_expanded_subexpressions = null;
        return ret;
    }
    return null;
}

/// Expands all expressions in `expr` and returns them as a newly
/// allocated slice.
fn maybeMacroExpandSubexpressions(self: MacroExpander, vm: *Vm, expr: []const Val) Error!?[]Val {
    var expandedExpr: ?[]Val = null;
    errdefer if (expandedExpr) |v| vm.allocator().free(v);
    for (expr, 0..expr.len) |sub_expr, idx| {
        if (try self.maybeMacroExpand(vm, sub_expr)) |v| {
            if (expandedExpr) |_| {} else {
                expandedExpr = try vm.allocator().dupe(Val, expr);
            }
            expandedExpr.?[idx] = v;
        }
    }
    return expandedExpr;
}
