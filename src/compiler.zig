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

const CompileError = error{ UnexpectedEmptyExpression, BadDefine } || Allocator.Error;

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

    fn compileOne(self: *Compiler, ast: Val) CompileError!void {
        switch (ast) {
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
