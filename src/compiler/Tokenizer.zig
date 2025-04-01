const std = @import("std");

const Tokenizer = @This();

source: []const u8,
next_idx: u32,

pub fn init(source: []const u8) Tokenizer {
    return Tokenizer{ .source = source, .next_idx = 0 };
}

pub fn next(self: *Tokenizer) ?Token {
    self.takeWhitespace();
    if (self.isDone()) {
        return null;
    }
    const next_char = self.source[self.next_idx];
    switch (next_char) {
        '(', ')' => {
            const token = Token{
                .token_type = if (next_char == '(') TokenType.OpenParen else TokenType.CloseParen,
                .location = Span{ .start = self.next_idx, .end = self.next_idx + 1 },
            };
            self.next_idx = token.location.end;
            return token;
        },
        else => {
            const start = self.next_idx;
            self.takeAtom();
            return Token{
                .token_type = TokenType.Atom,
                .location = Span{ .start = start, .end = self.next_idx },
            };
        },
    }
}

pub fn toArray(self: *Tokenizer, allocator: std.mem.Allocator) ![]Token {
    var ret = std.ArrayListUnmanaged(Token){};
    defer ret.deinit(allocator);
    while (self.next()) |token| {
        try ret.append(allocator, token);
    }
    return try allocator.dupe(Token, ret.items);
}

pub const Token = struct {
    token_type: TokenType,
    location: Span,

    pub fn text(self: Token, source: []const u8) []const u8 {
        return source[self.location.start..self.location.end];
    }
};

pub const Span = struct {
    start: u32,
    end: u32,
};

pub const TokenType = enum {
    OpenParen,
    CloseParen,
    Atom,
};

fn takeWhitespace(self: *Tokenizer) void {
    while (!self.isDone() and isWhitespace(self.source[self.next_idx])) {
        self.next_idx += 1;
    }
}

fn takeAtom(self: *Tokenizer) void {
    const start_idx = self.next_idx;
    while (!self.isDone()) {
        const next_char = self.source[self.next_idx];
        if (next_char == '"' and start_idx == self.next_idx) {
            return self.takeString();
        }
        if (isWhitespace(next_char) or next_char == '(' or next_char == ')' or next_char == '"') {
            return;
        }
        self.next_idx += 1;
    }
}

fn takeString(self: *Tokenizer) void {
    const start_idx = self.next_idx;
    var escape_next_char = false;
    while (!self.isDone()) {
        const next_char = self.source[self.next_idx];
        if (escape_next_char) {
            escape_next_char = false;
            self.next_idx += 1;
        } else if (next_char == '"' and start_idx != self.next_idx) {
            self.next_idx += 1;
            return;
        } else {
            escape_next_char = next_char == '\\';
            self.next_idx += 1;
        }
    }
}

fn isDone(self: Tokenizer) bool {
    const is_ok = self.next_idx < self.source.len;
    return !is_ok;
}

fn isWhitespace(ch: u8) bool {
    switch (ch) {
        ' ', '\t', '\n' => return true,
        else => return false,
    }
}

test "empty string is empty" {
    var tokenizer = Tokenizer.init("");
    try std.testing.expectEqual(null, tokenizer.next());
}

test "atoms are returned in order" {
    var tokenizer = Tokenizer.init("false true 3 4.5 \"6\"");
    const actual = try tokenizer.toArray(std.testing.allocator);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualDeep(&[_]Token{
        Token{ .token_type = TokenType.Atom, .location = Span{ .start = 0, .end = 5 } },
        Token{ .token_type = TokenType.Atom, .location = Span{ .start = 6, .end = 10 } },
        Token{ .token_type = TokenType.Atom, .location = Span{ .start = 11, .end = 12 } },
        Token{ .token_type = TokenType.Atom, .location = Span{ .start = 13, .end = 16 } },
        Token{ .token_type = TokenType.Atom, .location = Span{ .start = 17, .end = 20 } },
    }, actual);
}

test "string quotes are escaped" {
    var tokenizer = Tokenizer.init(" \"this \\\"word\\\" is quoted\" ");
    const actual = try tokenizer.toArray(std.testing.allocator);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualDeep(
        &[_]Token{
            Token{ .token_type = TokenType.Atom, .location = Span{ .start = 1, .end = 26 } },
        },
        actual,
    );
    try std.testing.expectEqualStrings(
        "\"this \\\"word\\\" is quoted\"",
        actual[0].text(tokenizer.source),
    );
}

test "parenthesis are parsed" {
    var tokenizer = Tokenizer.init("(+ 1 (- 4 5))(foo)");
    const actual = try tokenizer.toArray(std.testing.allocator);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualDeep(&[_]Token{
        Token{ .token_type = TokenType.OpenParen, .location = Span{ .start = 0, .end = 1 } },
        Token{ .token_type = TokenType.Atom, .location = Span{ .start = 1, .end = 2 } },
        Token{ .token_type = TokenType.Atom, .location = Span{ .start = 3, .end = 4 } },
        Token{ .token_type = TokenType.OpenParen, .location = Span{ .start = 5, .end = 6 } },
        Token{ .token_type = TokenType.Atom, .location = Span{ .start = 6, .end = 7 } },
        Token{ .token_type = TokenType.Atom, .location = Span{ .start = 8, .end = 9 } },
        Token{ .token_type = TokenType.Atom, .location = Span{ .start = 10, .end = 11 } },
        Token{ .token_type = TokenType.CloseParen, .location = Span{ .start = 11, .end = 12 } },
        Token{ .token_type = TokenType.CloseParen, .location = Span{ .start = 12, .end = 13 } },
        Token{ .token_type = TokenType.OpenParen, .location = Span{ .start = 13, .end = 14 } },
        Token{ .token_type = TokenType.Atom, .location = Span{ .start = 14, .end = 17 } },
        Token{ .token_type = TokenType.CloseParen, .location = Span{ .start = 17, .end = 18 } },
    }, actual);
}
