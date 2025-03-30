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
    EmptyKey,
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
            const expr = try Val.fromOwnedList(self.vm, try self.parseList());
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

pub fn parseAll(self: *AstBuilder, allocator: std.mem.Allocator) Error![]Ast {
    var ret = std.ArrayListUnmanaged(Ast){};
    defer ret.deinit(allocator);
    while (try self.next()) |ast| {
        try ret.append(allocator, ast);
    }
    return ret.toOwnedSlice(allocator);
}

fn parseList(self: *AstBuilder) Error![]Val {
    var list = std.ArrayListUnmanaged(Val){};
    defer list.deinit(self.vm.allocator());
    while (self.tokenizer.next()) |token| {
        switch (token.token_type) {
            Tokenizer.TokenType.OpenParen => {
                const sub_expr = try Val.fromOwnedList(self.vm, try self.parseList());
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

fn atomToVal(vm: *Vm, atom: []const u8) Error!Val {
    if (atom.len == 0) {
        return error.EmptyAtom;
    }
    if (std.mem.eql(u8, atom, "true")) {
        return Val.fromZig(vm, true);
    }
    if (std.mem.eql(u8, atom, "false")) {
        return Val.fromZig(vm, false);
    }
    if (atom[0] == '\"') {
        return stringAtomToVal(vm, atom);
    }
    if (atom[0] == ':') {
        return keyAtomToVal(vm, atom);
    }
    if (std.fmt.parseInt(i64, atom, 10)) |x| {
        return Val.fromZig(vm, x);
    } else |_| {}
    if (std.fmt.parseFloat(f64, atom)) |x| {
        return Val.fromZig(vm, x);
    } else |_| {}
    return Val.fromSymbolStr(vm, atom);
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
    // TODO: Use the owned value of ret.items to avoid allocation.
    return Val.fromZig(vm, ret.items);
}

fn keyAtomToVal(vm: *Vm, atom: []const u8) Error!Val {
    if (atom.len < 2) {
        return Error.EmptyKey;
    }
    std.debug.assert(atom[0] == ':');
    return Val.fromZig(vm, Symbol.Key{ .name = atom[1..] });
}

test "empty source produces no asts" {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();
    var ast_builder = AstBuilder.init(&vm, "");
    const actual = try ast_builder.parseAll(std.testing.allocator);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualDeep(
        &[_]Ast{},
        actual,
    );
}

test "parse atoms" {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();
    var ast_builder = AstBuilder.init(&vm, "0 1.0 \"string\" symbol 'quoted-symbol :key true false");
    const actual = try ast_builder.parseAll(std.testing.allocator);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualDeep(
        &[_]Ast{
            .{
                .location = .{ .start = 0, .end = 1 },
                .expr = try Val.fromZig(&vm, @as(i64, 0)),
            },
            .{
                .location = .{ .start = 2, .end = 5 },
                .expr = try Val.fromZig(&vm, @as(f64, 1)),
            },
            .{
                .location = .{ .start = 6, .end = 14 },
                .expr = actual[2].expr,
            },
            .{
                .location = .{ .start = 15, .end = 21 },
                .expr = try Val.fromZig(&vm, Symbol{ .quotes = 0, .name = "symbol" }),
            },
            .{
                .location = .{ .start = 22, .end = 36 },
                .expr = try Val.fromZig(&vm, Symbol{ .quotes = 1, .name = "quoted-symbol" }),
            },
            .{
                .location = .{ .start = 37, .end = 41 },
                .expr = try Val.fromZig(&vm, Symbol.Key{ .name = "key" }),
            },
            .{
                .location = .{ .start = 42, .end = 46 },
                .expr = try Val.fromZig(&vm, true),
            },
            .{
                .location = .{ .start = 47, .end = 52 },
                .expr = try Val.fromZig(&vm, false),
            },
        },
        actual,
    );
    try std.testing.expectEqualStrings(
        "string",
        try actual[2].expr.toZig([]const u8, &vm),
    );
}
