const std = @import("std");

const Allocator = std.mem.Allocator;
const Instruction = @import("instruction.zig").Instruction;
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

const Compiler = @This();

const Error = error{
    BadDefine,
    BadFunction,
    BadIf,
    BadWhen,
    ExpectedIdentifier,
    NotImplemented,
    ObjectNotFound,
    TooManyQuotes,
    UnexpectedEmptyExpression,
    WrongType,
} || Allocator.Error;

vm: *Vm,
instructions: std.ArrayListUnmanaged(Instruction),
// The symbol that is in thep process of being defined.
define_context: []const u8,
locals: std.ArrayListUnmanaged([]const u8),
internal_define_symbol: Symbol.Interned,
def_symbol: Symbol.Interned,
defun_symbol: Symbol.Interned,
function_symbol: Symbol.Interned,
do_symbol: Symbol.Interned,
if_symbol: Symbol.Interned,
when_symbol: Symbol.Interned,

/// Initialize a new compiler for a `Vm`.
pub fn init(vm: *Vm) !Compiler {
    return Compiler{
        .vm = vm,
        .instructions = .{},
        .define_context = "",
        .locals = .{},
        .internal_define_symbol = try (Symbol{ .quotes = 0, .name = "%define" }).intern(vm),
        .def_symbol = try (Symbol{ .quotes = 0, .name = "def" }).intern(vm),
        .defun_symbol = try (Symbol{ .quotes = 0, .name = "defun" }).intern(vm),
        .function_symbol = try (Symbol{ .quotes = 0, .name = "function" }).intern(vm),
        .do_symbol = try (Symbol{ .quotes = 0, .name = "do" }).intern(vm),
        .if_symbol = try (Symbol{ .quotes = 0, .name = "if" }).intern(vm),
        .when_symbol = try (Symbol{ .quotes = 0, .name = "when" }).intern(vm),
    };
}

pub fn deinit(self: *Compiler) void {
    self.instructions.deinit(self.allocator());
    self.locals.deinit(self.allocator());
}

pub fn currentExpr(self: *Compiler) []Instruction {
    return self.instructions.items;
}

pub fn compile(self: *Compiler, expr: Val) !void {
    try self.compileMultiExprs(&.{expr});
}

fn addLocal(self: *Compiler, name: []const u8) !void {
    try self.locals.append(self.allocator(), name);
}

fn localIdx(self: *Compiler, name: []const u8) ?u32 {
    if (self.locals.items.len == 0) return null;
    var idx = self.locals.items.len;
    while (idx > 0) {
        idx -= 1;
        if (std.mem.eql(u8, self.locals.items[idx], name)) return @intCast(idx);
    }
    return null;
}

fn compileMultiExprs(self: *Compiler, exprs: []const Val) !void {
    self.instructions.clearRetainingCapacity();
    for (exprs) |expr| {
        try self.compileOne(expr);
    }
}

fn ownedInstructions(self: *Compiler) ![]Instruction {
    return try self.instructions.toOwnedSlice(self.allocator());
}

fn macroExpand(self: *Compiler, ast: Val) !?Val {
    const expr = ast.toZig([]const Val, self.vm) catch return null;
    if (try self.macroExpandDef(expr)) |v| {
        return if (try self.macroExpand(v)) |x| x else v;
    }
    if (try self.macroExpandDefun(expr)) |v| {
        return if (try self.macroExpand(v)) |x| x else v;
    }
    if (try self.macroExpandWhen(expr)) |v| {
        return if (try self.macroExpand(v)) |x| x else v;
    }
    if (try self.macroExpandSubexpressions(expr)) |v| {
        return if (try self.macroExpand(v)) |x| x else v;
    }
    return null;
}

fn macroExpandSubexpressions(self: *Compiler, expr: []const Val) Error!?Val {
    var expandedExpr: ?[]Val = null;
    defer if (expandedExpr) |v| self.allocator().free(v);
    for (expr, 0..expr.len) |sub_expr, idx| {
        if (try self.macroExpand(sub_expr)) |v| {
            if (expandedExpr) |_| {} else {
                expandedExpr = try self.allocator().dupe(Val, expr);
            }
            expandedExpr.?[idx] = v;
        }
    }
    if (expandedExpr) |v| {
        const list_val = try Val.fromZig([]const Val, self.vm, v);
        expandedExpr = null;
        return list_val;
    }
    return null;
}

fn macroExpandDefun(self: *Compiler, expr: []const Val) !?Val {
    if (expr.len == 0) {
        return null;
    }
    const leading_symbol = if (expr[0].asInternedSymbol()) |x| x else return null;
    if (leading_symbol.eql(self.defun_symbol)) {
        if (expr.len < 4) {
            return Error.BadDefine;
        }
        const name = if (expr[1].asInternedSymbol()) |s| s else return Error.BadDefine;
        const args = expr[2];
        const body = expr[3..];
        var function_expr = try std.ArrayListUnmanaged(Val).initCapacity(
            self.allocator(),
            2 + body.len,
        );
        defer function_expr.deinit(self.allocator());
        function_expr.appendAssumeCapacity(self.function_symbol.toVal());
        function_expr.appendAssumeCapacity(args);
        function_expr.appendSliceAssumeCapacity(body);
        const function_expr_val = try Val.fromOwnedList(
            self.vm,
            try function_expr.toOwnedSlice(self.allocator()),
        );
        return try Val.fromZig(
            []const Val,
            self.vm,
            &.{
                self.internal_define_symbol.toVal(),
                name.quoted().toVal(),
                function_expr_val,
            },
        );
    }
    return null;
}

fn macroExpandWhen(self: *Compiler, expr: []const Val) !?Val {
    if (expr.len == 0) {
        return null;
    }
    const leading_symbol = if (expr[0].asInternedSymbol()) |x| x else return null;
    if (leading_symbol.eql(self.when_symbol)) {
        if (expr.len < 3) {
            return Error.BadWhen;
        }
        var body_expr = try self.allocator().dupe(Val, expr[1..]);
        defer self.allocator().free(body_expr);
        body_expr[0] = self.do_symbol.toVal();
        const expanded = try Val.fromZig([]const Val, self.vm, &.{
            self.if_symbol.toVal(),
            expr[1],
            try Val.fromZig([]const Val, self.vm, body_expr),
        });
        return expanded;
    }
    return null;
}

fn macroExpandDef(self: *Compiler, expr: []const Val) !?Val {
    if (expr.len == 0) {
        return null;
    }
    const leading_symbol = if (expr[0].asInternedSymbol()) |x| x else return null;
    if (leading_symbol.eql(self.def_symbol)) {
        if (expr.len != 3) {
            return Error.BadDefine;
        }
        const symbol = if (expr[1].asInternedSymbol()) |x| x.quoted() else return Error.ExpectedIdentifier;
        return try Val.fromZig([]const Val, self.vm, &.{
            self.internal_define_symbol.toVal(),
            symbol.toVal(),
            expr[2],
        });
    }
    return null;
}

fn compileOne(self: *Compiler, unexpanded_ast: Val) Error!void {
    const ast = if (try self.macroExpand(unexpanded_ast)) |v| v else unexpanded_ast;
    switch (ast.repr) {
        .list => |list_id| {
            const list = self.vm.objects.get(Val.List, list_id);
            try self.compileTree(list.?.list);
        },
        .symbol => |symbol| try self.compileSymbol(symbol),
        else => try self.instructions.append(
            self.allocator(),
            Instruction{ .push = ast },
        ),
    }
}

fn compileSymbol(self: *Compiler, symbol: Symbol.Interned) Error!void {
    if (symbol.quotes > 0) {
        try self.instructions.append(
            self.allocator(),
            Instruction{
                .push = try Val.fromZig(
                    Symbol.Interned,
                    self.vm,
                    .{ .quotes = symbol.quotes - 1, .id = symbol.id },
                ),
            },
        );
        return;
    }
    if (symbol.toSymbol(self.vm)) |named_symbol| {
        if (self.localIdx(named_symbol.name)) |idx| {
            try self.instructions.append(
                self.allocator(),
                Instruction{ .get_local = idx },
            );
            return;
        }
    }
    try self.instructions.append(
        self.allocator(),
        Instruction{ .deref = symbol },
    );
}

fn compileTree(self: *Compiler, nodes: []const Val) Error!void {
    if (nodes.len == 0) {
        return Error.UnexpectedEmptyExpression;
    }
    if (nodes[0].asInternedSymbol()) |leading_symbol| {
        if (leading_symbol.eql(self.function_symbol)) {
            if (nodes.len < 3) {
                return Error.BadFunction;
            }
            const args = nodes[1].toZig([]const Val, self.vm) catch return Error.BadFunction;
            return self.compileFunction(args, nodes[2..]);
        } else if (leading_symbol.eql(self.internal_define_symbol)) {
            if (nodes.len < 2) {
                return Error.BadDefine;
            }
            if (nodes[1].asInternedSymbol()) |s| {
                const old_context = self.define_context;
                defer self.define_context = old_context;
                self.define_context = blk: {
                    if (s.toSymbol(self.vm)) |name| {
                        if (name.quotes > 1) {
                            return Error.TooManyQuotes;
                        }
                        break :blk name.name;
                    } else {
                        break :blk "";
                    }
                };
            }
        } else if (leading_symbol.eql(self.if_symbol)) {
            switch (nodes.len) {
                3 => return self.compileIf(nodes[1], nodes[2], Val.init()),
                4 => return self.compileIf(nodes[1], nodes[2], nodes[3]),
                else => return Error.BadIf,
            }
        }
    }
    for (nodes) |node| {
        try self.compileOne(node);
    }
    try self.instructions.append(
        self.allocator(),
        Instruction{ .eval = @intCast(nodes.len) },
    );
}

fn compileIf(self: *Compiler, pred: Val, true_branch: Val, false_branch: Val) Error!void {
    try self.compileOne(pred);
    const jump_if_idx = self.instructions.items.len;
    try self.instructions.append(
        self.allocator(),
        .{ .jump_if = 0 },
    );
    const false_branch_start = self.instructions.items.len;
    try self.compileOne(false_branch);
    const false_branch_end = self.instructions.items.len;
    const jump_idx = self.instructions.items.len;
    try self.instructions.append(
        self.allocator(),
        Instruction{ .jump = 0 },
    );
    const true_branch_start = self.instructions.items.len;
    try self.compileOne(true_branch);
    const true_branch_end = self.instructions.items.len;
    self.instructions.items[jump_if_idx] = .{
        .jump_if = @intCast(false_branch_end - false_branch_start + 1),
    };
    self.instructions.items[jump_idx] = .{
        .jump = @intCast(true_branch_end - true_branch_start),
    };
}

fn compileFunction(self: *Compiler, args: []const Val, exprs: []const Val) !void {
    var function_compiler = try Compiler.init(self.vm);
    defer function_compiler.deinit();
    for (args) |arg| {
        const arg_symbol = arg.toZig(Symbol, self.vm) catch return Error.BadFunction;
        if (arg_symbol.quotes != 0) return Error.BadFunction;
        try function_compiler.addLocal(arg_symbol.name);
    }
    try function_compiler.compileMultiExprs(exprs);
    const bytecode = Val.ByteCodeFunction{
        .name = try self.allocator().dupe(u8, self.define_context),
        .instructions = try function_compiler.ownedInstructions(),
        .args = @intCast(args.len),
    };
    const bytecode_id = try self.vm.objects.put(Val.ByteCodeFunction, self.allocator(), bytecode);
    try self.instructions.append(
        self.allocator(),
        Instruction{ .push = bytecode_id.toVal() },
    );
}

fn allocator(self: *Compiler) std.mem.Allocator {
    return self.vm.allocator();
}
