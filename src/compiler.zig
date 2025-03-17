const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const TokenType = @import("tokenizer.zig").TokenType;
const Token = @import("tokenizer.zig").Token;
const Val = @import("val.zig").Val;
const ListVal = @import("val.zig").ListVal;
const Vm = @import("root.zig").Vm;
const Instruction = @import("instruction.zig").Instruction;
const Ast = @import("ast.zig").Ast;

pub const Compiler = struct {
    vm: *Vm,
    instructions: std.ArrayListUnmanaged(Instruction),

    pub fn init(vm: *Vm) Compiler {
        return Compiler{
            .vm = vm,
            .instructions = .{},
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.instructions.deinit(self.vm.allocator());
    }

    pub fn currentExpr(self: *Compiler) []Instruction {
        return self.instructions.items;
    }

    pub fn compile(self: *Compiler, ast: Ast) !void {
        self.instructions.clearRetainingCapacity();
        try self.compileOne(ast.ast);
    }

    fn compileOne(self: *Compiler, ast: Val) !void {
        switch (ast) {
            .list => |list| {
                const slice = self.vm.env.objects.lists.get(list);
                try self.compileTree(slice.?.list);
            },
            else => try self.instructions.append(
                self.allocator(),
                Instruction{ .push = ast },
            ),
        }
    }

    fn compileTree(self: *Compiler, nodes: []const Val) Allocator.Error!void {
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
