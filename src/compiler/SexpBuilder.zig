const std = @import("std");
const root = @import("../root.zig");

const SexprError = @import("../error.zig").SexpError;
const Symbol = Val.Symbol;
const Tokenizer = @import("Tokenizer.zig");
const Val = Vm.Val;
const Vm = root.Vm;

const SexpBuilder = @This();

tokenizer: Tokenizer,

/// Initialize an s expression builder for `source`.
pub fn init(source: []const u8) SexpBuilder {
    return SexpBuilder{
        .tokenizer = Tokenizer.init(source),
    };
}

/// Parse the next s-expression.
pub fn next(self: *SexpBuilder, vm: *Vm) SexprError!?Val {
    if (try self.nextWithLocation(vm)) |res| return res.expr;
    return null;
}

/// Contains an expression with information over its location.
pub const ExprWithLocation = struct {
    /// The location of the s-expression within source.
    location: Tokenizer.Span,
    /// The s expression.
    expr: Val,
};

/// Parse the next s-expression and return it along with its location
/// information.
pub fn nextWithLocation(self: *SexpBuilder, vm: *Vm) SexprError!?ExprWithLocation {
    const next_token: Tokenizer.Token = if (self.tokenizer.next()) |t| t else return null;
    const start = next_token.location.start;
    switch (next_token.token_type) {
        Tokenizer.TokenType.OpenParen => {
            const expr = try Val.fromOwnedList(vm, try self.parseList(vm));
            return .{
                .location = Tokenizer.Span{ .start = start, .end = self.tokenizer.next_idx },
                .expr = expr,
            };
        },
        Tokenizer.TokenType.CloseParen => return error.UnexpectedCloseParen,
        Tokenizer.TokenType.Atom => {
            const expr = try atomToVal(vm, next_token.text(self.tokenizer.source));
            return .{
                .location = Tokenizer.Span{ .start = start, .end = self.tokenizer.next_idx },
                .expr = expr,
            };
        },
    }
    return null;
}

/// Parse and return all s-expressions.
pub fn parseAll(self: *SexpBuilder, vm: *Vm, allocator: std.mem.Allocator) SexprError![]Val {
    var ret = std.ArrayListUnmanaged(Val){};
    defer ret.deinit(allocator);
    while (try self.next(vm)) |val| {
        try ret.append(allocator, val);
    }
    return ret.toOwnedSlice(allocator);
}

/// Parse all s-expressions and return them.
pub fn parseAllWithLocation(self: *SexpBuilder, vm: *Vm, allocator: std.mem.Allocator) SexprError![]ExprWithLocation {
    var ret = std.ArrayListUnmanaged(ExprWithLocation){};
    defer ret.deinit(allocator);
    while (try self.nextWithLocation(vm)) |ast| {
        try ret.append(allocator, ast);
    }
    return ret.toOwnedSlice(allocator);
}

fn parseList(self: *SexpBuilder, vm: *Vm) SexprError![]Val {
    var list = std.ArrayListUnmanaged(Val){};
    defer list.deinit(vm.allocator());
    while (self.tokenizer.next()) |token| {
        switch (token.token_type) {
            Tokenizer.TokenType.OpenParen => {
                const sub_expr = try Val.fromOwnedList(vm, try self.parseList(vm));
                try list.append(vm.allocator(), sub_expr);
            },
            Tokenizer.TokenType.CloseParen => return list.toOwnedSlice(vm.allocator()),
            Tokenizer.TokenType.Atom => {
                const val = try atomToVal(vm, token.text(self.tokenizer.source));
                try list.append(vm.allocator(), val);
            },
        }
    }
    return list.toOwnedSlice(vm.allocator());
}

fn atomToVal(vm: *Vm, atom: []const u8) SexprError!Val {
    if (atom.len == 0) {
        return error.EmptyAtom;
    }
    if (std.mem.eql(u8, atom, "true")) {
        return Val.from(vm, true);
    }
    if (std.mem.eql(u8, atom, "false")) {
        return Val.from(vm, false);
    }
    if (atom[0] == '\"') {
        return stringAtomToVal(vm, atom);
    }
    if (atom[0] == ':') {
        return keyAtomToVal(vm, atom);
    }
    if (std.fmt.parseInt(i64, atom, 10)) |x| {
        return Val.from(vm, x);
    } else |_| {}
    if (std.fmt.parseFloat(f64, atom)) |x| {
        return Val.from(vm, x);
    } else |_| {}
    const symbol = try Symbol.fromStr(atom);
    return Val.from(vm, symbol);
}

fn stringAtomToVal(vm: *Vm, atom: []const u8) SexprError!Val {
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
    return Val.from(vm, ret.items);
}

fn keyAtomToVal(vm: *Vm, atom: []const u8) SexprError!Val {
    if (atom.len < 2) {
        return SexprError.EmptyKey;
    }
    std.debug.assert(atom[0] == ':');
    return Val.from(vm, Symbol.Key{ .name = atom[1..] });
}

test "empty source produces no asts" {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();
    var sexp_builder = SexpBuilder.init("");
    const actual = try sexp_builder.parseAllWithLocation(&vm, std.testing.allocator);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualDeep(
        &[_]ExprWithLocation{},
        actual,
    );
}

test "parse atoms" {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();
    var sexp_builder = SexpBuilder.init("0 1.0 \"string\" symbol 'quoted-symbol :key true false");
    const actual = try sexp_builder.parseAllWithLocation(&vm, std.testing.allocator);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualDeep(
        &[_]ExprWithLocation{
            .{
                .location = .{ .start = 0, .end = 1 },
                .expr = try Val.from(&vm, 0),
            },
            .{
                .location = .{ .start = 2, .end = 5 },
                .expr = try Val.from(&vm, 1.0),
            },
            .{
                .location = .{ .start = 6, .end = 14 },
                .expr = actual[2].expr,
            },
            .{
                .location = .{ .start = 15, .end = 21 },
                .expr = try Val.from(&vm, try Symbol.fromStr("symbol")),
            },
            .{
                .location = .{ .start = 22, .end = 36 },
                .expr = try Val.from(&vm, Symbol{ ._quotes = 1, ._name = "quoted-symbol" }),
            },
            .{
                .location = .{ .start = 37, .end = 41 },
                .expr = try Val.from(&vm, Symbol.Key{ .name = "key" }),
            },
            .{
                .location = .{ .start = 42, .end = 46 },
                .expr = try Val.from(&vm, true),
            },
            .{
                .location = .{ .start = 47, .end = 52 },
                .expr = try Val.from(&vm, false),
            },
        },
        actual,
    );
    try std.testing.expectEqualStrings(
        "string",
        try actual[2].expr.to([]const u8, &vm),
    );
}
