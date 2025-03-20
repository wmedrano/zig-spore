const std = @import("std");
const Allocator = std.mem.Allocator;
const ByteCodeFunction = @import("val.zig").ByteCodeFunction;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const TokenType = @import("tokenizer.zig").TokenType;
const Token = @import("tokenizer.zig").Token;
const Val = @import("val.zig").Val;
const ListVal = @import("val.zig").ListVal;
const Symbol = @import("val.zig").Symbol;
const Vm = @import("vm.zig").Vm;
const Instruction = @import("instruction.zig").Instruction;
const Ast = @import("ast.zig").Ast;

const CompileError = error{ ExpectedIdentifier, UnexpectedEmptyExpression, BadDefine, BadLambda, NotImplemented } || Allocator.Error;

pub const Compiler = struct {
    vm: *Vm,
    instructions: std.ArrayListUnmanaged(Instruction),
    def_symbol: Symbol,
    defun_symbol: Symbol,
    lambda_symbol: Symbol,

    pub fn init(vm: *Vm) !Compiler {
        return Compiler{
            .vm = vm,
            .instructions = .{},
            .def_symbol = (try vm.newSymbol("def")),
            .defun_symbol = (try vm.newSymbol("defun")),
            .lambda_symbol = (try vm.newSymbol("lambda")),
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.instructions.deinit(self.allocator());
    }

    pub fn currentExpr(self: *Compiler) []Instruction {
        return self.instructions.items;
    }

    pub fn ownedInstructions(self: *Compiler) ![]Instruction {
        return try self.instructions.toOwnedSlice(self.allocator());
    }

    pub fn compile(self: *Compiler, ast: Ast) !void {
        const exprs = [1]Val{ast.ast};
        return self.compileMultiExprs(&exprs);
    }

    pub fn compileMultiExprs(self: *Compiler, exprs: []const Val) !void {
        self.instructions.clearRetainingCapacity();
        for (exprs) |expr| {
            try self.compileOne(expr);
        }
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

    fn macroExpandSubexpressions(self: *Compiler, ast: Val) CompileError!?Val {
        const exprs = if (ast.asList(self.vm)) |list| list.list else return null;
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
            const list_val = try self.vm.env.objects.put(
                ListVal,
                self.allocator(),
                ListVal{ .list = v },
            );
            expandedExpr = null;
            return list_val.toVal();
        }
        return null;
    }

    fn macroExpandDefun(self: *Compiler, ast: Val) !?Val {
        const expr = if (ast.asList(self.vm)) |list| list.list else return null;
        if (expr.len == 0) {
            return null;
        }
        const leading_symbol = if (expr[0].asSymbol()) |x| x else return null;
        if (leading_symbol.eql(self.defun_symbol)) {
            if (expr.len < 4) {
                return CompileError.BadDefine;
            }
            const name = if (expr[1].asSymbol()) |s| s else return CompileError.BadDefine;
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
            const lambda_expr_val = try self.vm.env.objects.put(
                ListVal,
                self.allocator(),
                ListVal{
                    .list = try lambda_expr.toOwnedSlice(self.allocator()),
                },
            );
            const new_expr = try self.vm.env.objects.put(
                ListVal,
                self.allocator(),
                ListVal{
                    .list = try self.allocator().dupe(Val, &[3]Val{
                        (try self.vm.newSymbol("%define")).toVal(),
                        name.quoted().toVal(),
                        lambda_expr_val.toVal(),
                    }),
                },
            );
            return new_expr.toVal();
        }
        return null;
    }

    fn macroExpandDef(self: *Compiler, ast: Val) !?Val {
        const expr = if (ast.asList(self.vm)) |list| list.list else return null;
        if (expr.len == 0) {
            return null;
        }
        const leading_symbol = if (expr[0].asSymbol()) |x| x else return null;
        if (leading_symbol.eql(self.def_symbol)) {
            if (expr.len != 3) {
                return CompileError.BadDefine;
            }
            const symbol = if (expr[1].asSymbol()) |x| x.quoted() else return CompileError.ExpectedIdentifier;
            const new_expr = try self.vm.env.objects.put(ListVal, self.allocator(), ListVal{
                .list = try self.allocator().dupe(Val, &[3]Val{
                    (try self.vm.newSymbol("%define")).toVal(),
                    symbol.toVal(),
                    expr[2],
                }),
            });
            return new_expr.toVal();
        }
        return null;
    }

    fn compileOne(self: *Compiler, ast: Val) CompileError!void {
        const expanded_ast = if (try self.macroExpand(ast)) |v| v else ast;
        switch (expanded_ast) {
            .list => |list_id| {
                const list = self.vm.env.objects.get(ListVal, list_id);
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
                        .push = Val{
                            .symbol = Symbol{
                                .quotes = symbol.quotes - 1,
                                .id = symbol.id,
                            },
                        },
                    },
                );
            },
            else => try self.instructions.append(
                self.allocator(),
                Instruction{ .push = ast },
            ),
        }
    }

    fn compileTree(self: *Compiler, nodes: []const Val) CompileError!void {
        if (nodes.len == 0) {
            return CompileError.UnexpectedEmptyExpression;
        }
        if (nodes[0].asSymbol()) |leading_symbol| {
            if (leading_symbol.eql(self.lambda_symbol)) {
                if (nodes.len < 3) {
                    return CompileError.BadLambda;
                }
                const args = if (nodes[1].asList(self.vm)) |args| args.list else return CompileError.BadLambda;
                return self.compileLambda(args, nodes[2..]);
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
            return CompileError.NotImplemented;
        }
        var lambda_compiler = try Compiler.init(self.vm);
        try lambda_compiler.compileMultiExprs(exprs);
        const bytecode = ByteCodeFunction{
            .name = try self.allocator().dupe(u8, "function"),
            .instructions = try lambda_compiler.ownedInstructions(),
        };
        const bytecode_id = try self.vm.env.objects.put(ByteCodeFunction, self.allocator(), bytecode);
        try self.instructions.append(
            self.allocator(),
            Instruction{ .push = bytecode_id.toVal() },
        );
    }

    fn allocator(self: *Compiler) std.mem.Allocator {
        return self.vm.allocator();
    }
};
