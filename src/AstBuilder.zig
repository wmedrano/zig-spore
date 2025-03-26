const std = @import("std");

const Symbol = @import("Symbol.zig");
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

pub const Error = error{
    TooManyQuotes,
    EmptySymbol,
    EmptyAtom,
    BadString,
    UnexpectedCloseParen,
} || std.mem.Allocator.Error;

pub fn init(vm: *Vm, source: []const u8) AstBuilder {
    return AstBuilder{
        .vm = vm,
        .tokenizer = Tokenizer.init(source),
    };
}

pub fn next(self: *AstBuilder) Error!?Ast {
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
        Tokenizer.TokenType.Atom => {
            const expr = try atomToVal(self.vm, next_token.text(self.tokenizer.source));
            return Ast{
                .location = Tokenizer.Span{ .start = start, .end = self.tokenizer.next_idx },
                .expr = expr,
            };
        },
    }
    return null;
}

fn parseList(self: *AstBuilder) Error![]Val {
    var list = std.ArrayListUnmanaged(Val){};
    defer list.deinit(self.vm.allocator());
    while (self.tokenizer.next()) |token| {
        switch (token.token_type) {
            Tokenizer.TokenType.OpenParen => {
                const sub_expr = try ownedSliceToVal(self.vm, try self.parseList());
                try list.append(self.vm.allocator(), sub_expr);
            },
            Tokenizer.TokenType.CloseParen => return list.toOwnedSlice(self.vm.allocator()),
            Tokenizer.TokenType.Atom => {
                const val = try atomToVal(self.vm, token.text(self.tokenizer.source));
                try list.append(self.vm.allocator(), val);
            },
        }
    }
    return list.toOwnedSlice(self.vm.allocator());
}

fn ownedSliceToVal(vm: *Vm, slice: []Val) Error!Val {
    return Val.fromOwnedList(vm, slice);
}

fn atomToVal(vm: *Vm, atom: []const u8) Error!Val {
    if (atom.len == 0) {
        return error.EmptyAtom;
    }
    if (std.mem.eql(u8, atom, "true")) {
        return Val.fromBool(true);
    }
    if (std.mem.eql(u8, atom, "false")) {
        return Val.fromBool(true);
    }
    if (atom[0] == '\"') {
        return stringAtomToVal(vm, atom);
    }
    if (std.fmt.parseInt(i64, atom, 10)) |x| {
        return Val.fromInt(x);
    } else |_| {}
    if (std.fmt.parseFloat(f64, atom)) |x| {
        return Val.fromFloat(x);
    } else |_| {}
    const symbol = try Symbol.fromStr(atom);
    return Val.fromSymbol(vm, symbol);
}

fn stringAtomToVal(vm: *Vm, atom: []const u8) Error!Val {
    if (atom.len < 2) {
        return error.BadString;
    }
    if (atom[0] != '"' or atom[atom.len - 1] != '"') {
        return error.BadString;
    }
    var ret = std.ArrayListUnmanaged(u8){};
    defer ret.deinit(vm.allocator());
    var escaped = false;
    for (atom[1 .. atom.len - 1]) |ch| {
        if (escaped) {
            escaped = false;
            try ret.append(vm.allocator(), ch);
        } else {
            switch (ch) {
                '\\' => escaped = true,
                '"' => return error.BadString,
                else => try ret.append(vm.allocator(), ch),
            }
        }
    }
    if (escaped) {
        return error.BadString;
    }
    const s = try ret.toOwnedSlice(vm.allocator());
    return Val.fromOwnedString(vm, s);
}
