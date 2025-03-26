const std = @import("std");

const Allocator = std.mem.Allocator;
const Instruction = @import("instruction.zig").Instruction;
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

const Compiler = @This();

const Error = error{
    BadDefine,
    BadLambda,
    ExpectedIdentifier,
    NotImplemented,
    TooManyQuotes,
    UnexpectedEmptyExpression,
} || Symbol.FromStrError || Allocator.Error;

vm: *Vm,
instructions: std.ArrayListUnmanaged(Instruction),
// The symbol that is in thep process of being defined.
define_context: []const u8,
internal_define_symbol: Val.InternedSymbol,
def_symbol: Val.InternedSymbol,
defun_symbol: Val.InternedSymbol,
lambda_symbol: Val.InternedSymbol,

/// Initialize a new compiler for a `Vm`.
pub fn init(vm: *Vm) !Compiler {
    return Compiler{
        .vm = vm,
        .instructions = .{},
        .define_context = "",
        .internal_define_symbol = try Val.InternedSymbol.fromSymbolStr(vm, "%define"),
        .def_symbol = try Val.InternedSymbol.fromSymbolStr(vm, "def"),
        .defun_symbol = try Val.InternedSymbol.fromSymbolStr(vm, "defun"),
        .lambda_symbol = try Val.InternedSymbol.fromSymbolStr(vm, "lambda"),
    };
}

pub fn deinit(self: *Compiler) void {
    self.instructions.deinit(self.allocator());
}

pub fn currentExpr(self: *Compiler) []Instruction {
    return self.instructions.items;
}

pub fn compile(self: *Compiler, expr: Val) !void {
    try self.compileMultiExprs(&[1]Val{expr});
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
    var ret = ast;
    var didReplace = false;
    if (try self.macroExpandSubexpressions(ret)) |v| {
        ret = v;
        didReplace = true;
    }
    if (try self.macroExpandDef(ret)) |v| {
        ret = v;
        didReplace = true;
    }
    if (try self.macroExpandDefun(ret)) |v| {
        ret = v;
        didReplace = true;
    }
    if (didReplace) return ret else return null;
}

fn macroExpandSubexpressions(self: *Compiler, ast: Val) Error!?Val {
    const exprs = if (ast.asList(self.vm.*)) |list| list else return null;
    var expandedExpr: ?[]Val = null;
    defer if (expandedExpr) |v| self.allocator().free(v);
    for (exprs, 0..exprs.len) |sub_expr, idx| {
        if (try self.macroExpand(sub_expr)) |v| {
            if (expandedExpr) |_| {} else {
                expandedExpr = try self.allocator().dupe(Val, exprs);
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

fn macroExpandDefun(self: *Compiler, ast: Val) !?Val {
    const expr = if (ast.asList(self.vm.*)) |list| list else return null;
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
        var lambda_expr = try std.ArrayListUnmanaged(Val).initCapacity(
            self.allocator(),
            2 + body.len,
        );
        defer lambda_expr.deinit(self.allocator());
        lambda_expr.appendAssumeCapacity(self.lambda_symbol.toVal());
        lambda_expr.appendAssumeCapacity(args);
        lambda_expr.appendSliceAssumeCapacity(body);
        const lambda_expr_val = try Val.fromOwnedList(
            self.vm,
            try lambda_expr.toOwnedSlice(self.allocator()),
        );
        return try Val.fromZig(
            []const Val,
            self.vm,
            &[_]Val{
                self.internal_define_symbol.toVal(),
                name.quoted().toVal(),
                lambda_expr_val,
            },
        );
    }
    return null;
}

fn macroExpandDef(self: *Compiler, ast: Val) !?Val {
    const expr = if (ast.asList(self.vm.*)) |list| list else return null;
    if (expr.len == 0) {
        return null;
    }
    const leading_symbol = if (expr[0].asInternedSymbol()) |x| x else return null;
    if (leading_symbol.eql(self.def_symbol)) {
        if (expr.len != 3) {
            return Error.BadDefine;
        }
        const symbol = if (expr[1].asInternedSymbol()) |x| x.quoted() else return Error.ExpectedIdentifier;
        return try Val.fromZig([]const Val, self.vm, &[3]Val{
            self.internal_define_symbol.toVal(),
            symbol.toVal(),
            expr[2],
        });
    }
    return null;
}

fn compileOne(self: *Compiler, ast: Val) Error!void {
    const expanded_ast = if (try self.macroExpand(ast)) |v| v else ast;
    switch (expanded_ast.repr) {
        .list => |list_id| {
            const list = self.vm.objects.get(Val.List, list_id);
            try self.compileTree(list.?.list);
        },
        .symbol => |symbol| {
            if (symbol.quotes == 0) {
                try self.instructions.append(
                    self.allocator(),
                    Instruction{ .deref = symbol },
                );
                return;
            }
            try self.instructions.append(
                self.allocator(),
                Instruction{
                    .push = try Val.fromZig(
                        Val.InternedSymbol,
                        self.vm,
                        .{ .quotes = symbol.quotes - 1, .id = symbol.id },
                    ),
                },
            );
        },
        else => try self.instructions.append(
            self.allocator(),
            Instruction{ .push = ast },
        ),
    }
}

fn compileTree(self: *Compiler, nodes: []const Val) Error!void {
    if (nodes.len == 0) {
        return Error.UnexpectedEmptyExpression;
    }
    if (nodes[0].asInternedSymbol()) |leading_symbol| {
        if (leading_symbol.eql(self.lambda_symbol)) {
            if (nodes.len < 3) {
                return Error.BadLambda;
            }
            const args = if (nodes[1].asList(self.vm.*)) |args| args else return Error.BadLambda;
            return self.compileLambda(args, nodes[2..]);
        } else if (leading_symbol.eql(self.internal_define_symbol)) {
            if (nodes.len < 2) {
                return Error.BadDefine;
            }
            if (nodes[1].asInternedSymbol()) |s| {
                const old_context = self.define_context;
                defer self.define_context = old_context;
                self.define_context = blk: {
                    if (s.toSymbol(self.vm.*)) |name| {
                        if (name.quotes > 1) {
                            return Error.TooManyQuotes;
                        }
                        break :blk name.name;
                    } else {
                        break :blk "";
                    }
                };
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

fn compileLambda(self: *Compiler, args: []const Val, exprs: []const Val) !void {
    if (args.len != 0) {
        return Error.NotImplemented;
    }
    var lambda_compiler = try Compiler.init(self.vm);
    try lambda_compiler.compileMultiExprs(exprs);
    const bytecode = Val.ByteCodeFunction{
        .name = try self.allocator().dupe(u8, self.define_context),
        .instructions = try lambda_compiler.ownedInstructions(),
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
