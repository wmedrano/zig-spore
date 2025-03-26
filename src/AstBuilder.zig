const std = @import("std");

const Tokenizer = @import("Tokenizer.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

const AstBuilder = @This();

pub const Ast = struct {
    location: Tokenizer.Span,
    expr: Val,
};

vm: *Vm,
tokenizer: Tokenizer,

pub fn init(vm: *Vm, source: []const u8) AstBuilder {
    return AstBuilder{
        .vm = vm,
        .tokenizer = Tokenizer.init(source),
    };
}

pub fn next(self: *AstBuilder) !?Ast {
    const next_token: Tokenizer.Token = if (self.tokenizer.next()) |t| t else return null;
    const start = next_token.location.start;
    switch (next_token.token_type) {
        Tokenizer.TokenType.OpenParen => {
            const expr = try ownedSliceToVal(self.vm, try self.parseList());
            return Ast{
                .location = Tokenizer.Span{ .start = start, .end = self.tokenizer.next_idx },
                .expr = expr,
            };
        },
        Tokenizer.TokenType.CloseParen => return error.UnexpectedCloseParen,
        Tokenizer.TokenType.Identifier => {
            const expr = try identifierToVal(self.vm, next_token.text(self.tokenizer.source));
            return Ast{
                .location = Tokenizer.Span{ .start = start, .end = self.tokenizer.next_idx },
                .expr = expr,
            };
        },
    }
    return null;
}

fn parseList(self: *AstBuilder) ![]Val {
    var list = std.ArrayListUnmanaged(Val){};
    defer list.deinit(self.vm.allocator());
    while (self.tokenizer.next()) |token| {
        switch (token.token_type) {
            Tokenizer.TokenType.OpenParen => {
                const sub_expr = try ownedSliceToVal(self.vm, try self.parseList());
                try list.append(self.vm.allocator(), sub_expr);
            },
            Tokenizer.TokenType.CloseParen => return list.toOwnedSlice(self.vm.allocator()),
            Tokenizer.TokenType.Identifier => {
                const val = try identifierToVal(self.vm, token.text(self.tokenizer.source));
                try list.append(self.vm.allocator(), val);
            },
        }
    }
    return list.toOwnedSlice(self.vm.allocator());
}

fn ownedSliceToVal(vm: *Vm, slice: []Val) !Val {
    return Val.fromOwnedList(vm, slice);
}

fn identifierToVal(vm: *Vm, identifier: []const u8) !Val {
    if (std.mem.eql(u8, identifier, "true")) {
        return Val.fromBool(true);
    }
    if (std.mem.eql(u8, identifier, "false")) {
        return Val.fromBool(true);
    }
    if (std.fmt.parseInt(i64, identifier, 10)) |x| {
        return Val.fromInt(x);
    } else |_| {}
    if (std.fmt.parseFloat(f64, identifier)) |x| {
        return Val.fromFloat(x);
    } else |_| {}
    return (try vm.newSymbol(identifier)).toVal();
}
