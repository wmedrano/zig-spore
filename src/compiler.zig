const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const TokenType = @import("tokenizer.zig").TokenType;
const Token = @import("tokenizer.zig").Token;
const Val = @import("val.zig").Val;
const ListVal = @import("val.zig").ListVal;
const Symbol = @import("val.zig").Symbol;
const Vm = @import("vm.zig").Vm;
const Instruction = @import("instruction.zig").Instruction;
const Ast = @import("ast.zig").Ast;

const CompileError = error{ ExpectedIdentifier, UnexpectedEmptyExpression, BadDefine } || Allocator.Error;

pub const Compiler = struct {
    vm: *Vm,
    instructions: std.ArrayListUnmanaged(Instruction),
    def_symbol: Symbol,

    pub fn init(vm: *Vm) !Compiler {
        return Compiler{
            .vm = vm,
            .instructions = .{},
            .def_symbol = (try vm.newSymbol("def")),
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.instructions.deinit(self.allocator());
    }

    pub fn currentExpr(self: *Compiler) []Instruction {
        return self.instructions.items;
    }

    pub fn compile(self: *Compiler, ast: Ast) !void {
        self.instructions.clearRetainingCapacity();
        try self.compileOne(ast.ast);
    }

    fn expandAst(self: *Compiler, ast: Val) !?Val {
        var ret = ast;
        var didReplace = false;
        if (try self.expandSubExpressions(ret)) |v| {
            ret = v;
            didReplace = true;
        }
        if (try self.expandDefAst(ret)) |v| {
            ret = v;
            didReplace = true;
        }
        if (didReplace) return ret else return null;
    }

    fn expandSubExpressions(self: *Compiler, ast: Val) CompileError!?Val {
        const exprs = switch (ast) {
            .list => |id| self.vm.env.objects.get(ListVal, id).?.list,
            else => return null,
        };
        var expandedExpr: ?[]Val = null;
        defer if (expandedExpr) |v| self.allocator().free(v);
        for (exprs, 0..exprs.len) |sub_expr, idx| {
            if (try self.expandAst(sub_expr)) |v| {
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

    fn expandDefAst(self: *Compiler, ast: Val) !?Val {
        const expr = switch (ast) {
            .list => |id| self.vm.env.objects.get(ListVal, id).?.list,
            else => return null,
        };
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
        const expanded_ast = if (try self.expandAst(ast)) |v| v else ast;
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
        for (nodes) |node| {
            try self.compileOne(node);
        }
        try self.instructions.append(
            self.allocator(),
            Instruction{ .eval = @intCast(nodes.len) },
        );
    }

    fn allocator(self: *Compiler) std.mem.Allocator {
        return self.vm.allocator();
    }
};
