const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const TokenType = @import("tokenizer.zig").TokenType;
const Token = @import("tokenizer.zig").Token;
const Val = @import("val.zig").Val;

pub const Compiler = struct {
    tokenizer: Tokenizer,

    pub fn init(source: []const u8) Compiler {
        return Compiler{
            .tokenizer = Tokenizer.init(source),
        };
    }

    pub fn next(self: *Compiler) !?Val {
        const next_token: Token = if (self.tokenizer.next()) |t| t else return null;
        switch (next_token.token_type) {
            TokenType.OpenParen => return Val{ .void = {} },
            TokenType.CloseParen => return Val{ .void = {} },
            TokenType.Identifier => return identifierToVal(next_token.text(self.tokenizer.source)),
        }
        return null;
    }
};

fn identifierToVal(identifier: []const u8) Val {
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
    return Val{ .void = {} };
}
