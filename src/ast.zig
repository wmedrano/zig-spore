const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const TokenType = @import("tokenizer.zig").TokenType;
const Token = @import("tokenizer.zig").Token;
const Val = @import("val.zig").Val;
const ListVal = @import("val.zig").ListVal;
const Vm = @import("vm.zig").Vm;

pub const Ast = struct {
    ast: Val,
};

pub const AstBuilder = struct {
    vm: *Vm,
    tokenizer: Tokenizer,

    pub fn init(vm: *Vm, source: []const u8) AstBuilder {
        return AstBuilder{
            .vm = vm,
            .tokenizer = Tokenizer.init(source),
        };
    }

    pub fn next(self: *AstBuilder) !?Ast {
        const next_token: Token = if (self.tokenizer.next()) |t| t else return null;
        switch (next_token.token_type) {
            TokenType.OpenParen => {
                const ast_val = try ownedSliceToVal(self.vm, try self.parseList());
                return Ast{ .ast = ast_val };
            },
            TokenType.CloseParen => return error.UnexpectedCloseParen,
            TokenType.Identifier => {
                const val = try identifierToVal(self.vm, next_token.text(self.tokenizer.source));
                return Ast{ .ast = val };
            },
        }
        return null;
    }

    fn parseList(self: *AstBuilder) ![]Val {
        var list = std.ArrayListUnmanaged(Val){};
        defer list.deinit(self.vm.allocator());
        while (self.tokenizer.next()) |token| {
            switch (token.token_type) {
                TokenType.OpenParen => {
                    const sub_expr = try ownedSliceToVal(self.vm, try self.parseList());
                    try list.append(self.vm.allocator(), sub_expr);
                },
                TokenType.CloseParen => return list.toOwnedSlice(self.vm.allocator()),
                TokenType.Identifier => {
                    const val = try identifierToVal(self.vm, token.text(self.tokenizer.source));
                    try list.append(self.vm.allocator(), val);
                },
            }
        }
        return list.toOwnedSlice(self.vm.allocator());
    }
};

fn ownedSliceToVal(vm: *Vm, slice: []Val) !Val {
    const list = ListVal{
        .list = slice,
    };
    const id = try vm.env.objects.lists.put(vm.allocator(), list);
    return Val{ .list = id };
}

fn identifierToVal(vm: *Vm, identifier: []const u8) !Val {
    if (std.mem.eql(u8, identifier, "true")) {
        return Val{ .bool = true };
    }
    if (std.mem.eql(u8, identifier, "false")) {
        return Val{ .bool = false };
    }
    if (std.fmt.parseInt(i64, identifier, 10)) |x| {
        return Val{ .int = x };
    } else |_| {}
    if (std.fmt.parseFloat(f64, identifier)) |x| {
        return Val{ .float = x };
    } else |_| {}
    return vm.newSymbol(identifier);
}
