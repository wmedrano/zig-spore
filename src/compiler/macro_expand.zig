const std = @import("std");
const root = @import("../root.zig");

const Error = root.Error;
const NativeFunction = Val.NativeFunction;
const Symbol = Val.Symbol;
const Val = Vm.Val;
const Vm = root.Vm;
const converters = @import("../converters.zig");
const macros = @import("../builtins/macros.zig");

/// Expands all the macros in `expr`.
pub fn expand(vm: *Vm, expr: Val) Error!Val {
    if (try maybeMacroExpand(vm, expr)) |v| return v else return expr;
}

/// Similar to `expand` but returns `null` if there is no macro
/// in `expr`.
fn maybeMacroExpand(vm: *Vm, expr: Val) !?Val {
    const subexpressions = expr.to([]const Val, vm) catch return null;
    if (subexpressions.len == 0) return null;
    const leading_val = if (subexpressions.len == 0) return null else subexpressions[0];
    const leading_symbol = leading_val.to(Symbol.Interned, {}) catch return null;
    const macro_fn: ?*const NativeFunction = blk: {
        const maybe_val = if (vm.global.getValue(leading_symbol)) |v| v else break :blk null;
        if (!maybe_val.is(*const NativeFunction)) break :blk null;
        const macro_func = try maybe_val.to(*const NativeFunction, vm);
        if (!macro_func.metadata.is_macro) break :blk null;
        break :blk macro_func;
    };
    if (macro_fn) |f| {
        const expanded = try f.executeWith(vm, subexpressions[1..]);
        return try expand(vm, expanded);
    }
    var maybe_expanded_subexpressions: ?[]Val = try maybeExpandSubexpressions(vm, subexpressions);
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
fn maybeExpandSubexpressions(vm: *Vm, expr: []const Val) Error!?[]Val {
    var expandedExpr: ?[]Val = null;
    errdefer if (expandedExpr) |v| vm.allocator().free(v);
    for (expr, 0..expr.len) |sub_expr, idx| {
        if (try maybeMacroExpand(vm, sub_expr)) |v| {
            if (expandedExpr) |_| {} else {
                expandedExpr = try vm.allocator().dupe(Val, expr);
            }
            expandedExpr.?[idx] = v;
        }
    }
    return expandedExpr;
}

test "no macro expansion returns null" {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const expr = try Val.from(&vm, @as([]const Val, &.{
        try Val.from(&vm, try Symbol.fromStr("+")),
        try Val.from(&vm, 1),
        try Val.from(&vm, 2),
    }));
    const expanded = try expand(&vm, expr);
    try std.testing.expectFmt("(+ 1 2)", "{any}", .{expanded.formatted(&vm)});
}

test "def macro expansion" {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const expr = try Val.from(&vm, @as([]const Val, &.{
        try Val.from(&vm, try Symbol.fromStr("def")),
        try Val.from(&vm, try Symbol.fromStr("x")),
        try Val.from(&vm, 123),
    }));
    const expanded = try expand(&vm, expr);
    try std.testing.expectFmt("(%define 'x 123)", "{any}", .{expanded.formatted(&vm)});
}

test "when macro expansion" {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const expr = try Val.from(&vm, @as([]const Val, &.{
        try Val.from(&vm, try Symbol.fromStr("when")),
        try Val.from(&vm, true),
        try Val.from(&vm, 123),
    }));
    const expanded = try expand(&vm, expr);
    try std.testing.expectFmt("(if true (do 123))", "{any}", .{expanded.formatted(&vm)});

    const expr_false = try Val.from(&vm, @as([]const Val, &.{
        try Val.from(&vm, try Symbol.fromStr("when")),
        try Val.from(&vm, false),
        try Val.from(&vm, 123),
        try Val.from(&vm, 456),
    }));
    const expanded_false = try expand(&vm, expr_false);
    try std.testing.expectFmt("(if false (do 123 456))", "{any}", .{expanded_false.formatted(&vm)});
}

test "nested macro expansion" {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const expr = try Val.from(&vm, @as([]const Val, &.{
        try Val.from(&vm, try Symbol.fromStr("def")),
        try Val.from(&vm, try Symbol.fromStr("y")),
        try Val.from(&vm, @as([]const Val, &.{
            try Val.from(&vm, try Symbol.fromStr("when")),
            try Val.from(&vm, true),
            try Val.from(&vm, 456),
        })),
    }));
    const expanded = try expand(&vm, expr);
    try std.testing.expectFmt("(%define 'y (if true (do 456)))", "{any}", .{expanded.formatted(&vm)});
}
