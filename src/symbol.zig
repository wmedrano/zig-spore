const std = @import("std");

const Symbol = @import("val.zig").Symbol;

pub const NamedSymbol = struct {
    quotes: u2,
    name: []const u8,

    pub fn init(str: []const u8) NamedSymbol {
        var quotes: usize = 0;
        while (quotes < str.len and str[quotes] == '\'') {
            quotes += 1;
        }
        if (quotes > 3) {
            quotes = 3;
        }
        return NamedSymbol{
            .quotes = @intCast(quotes),
            .name = str[quotes..],
        };
    }
};

pub const SymbolTable = struct {
    symbols: std.ArrayListUnmanaged([]const u8) = .{},
    name_to_symbol: std.StringHashMapUnmanaged(u30) = .{},

    pub fn deinit(self: *SymbolTable, allocator: std.mem.Allocator) void {
        for (self.symbols.items) |k| {
            allocator.free(k);
        }
        self.symbols.deinit(allocator);
        self.name_to_symbol.deinit(allocator);
    }

    pub fn strToSymbol(self: *SymbolTable, allocator: std.mem.Allocator, str: NamedSymbol) !Symbol {
        if (self.name_to_symbol.get(str.name)) |id| {
            return Symbol{
                .quotes = str.quotes,
                .id = id,
            };
        }
        const name = try allocator.dupe(u8, str.name);
        const id = Symbol{ .quotes = str.quotes, .id = @intCast(self.size()) };
        try self.symbols.append(allocator, name);
        try self.name_to_symbol.put(allocator, name, id.id);
        return id;
    }

    pub fn symbolToStr(self: *const SymbolTable, symbol: Symbol) ?NamedSymbol {
        if (symbol.id < self.size()) {
            return NamedSymbol{
                .quotes = symbol.quotes,
                .name = self.symbols.items[symbol.id],
            };
        }
        return null;
    }

    fn size(self: *const SymbolTable) u32 {
        return @intCast(self.symbols.items.len);
    }
};

fn countQuotes(s: []const u8) u2 {
    const u2_max = 3;
    const len = if (s.len > u2_max) u2_max else s.len;
    for (0..len) |idx| {
        if (s[idx] != '\'') {
            return @intCast(idx);
        }
    }
    return len;
}

test "symbols from different but equivalent strings are bitwise equal" {
    var symbol_table = SymbolTable{};
    defer symbol_table.deinit(std.testing.allocator);
    const symbol_1 = try symbol_table.strToSymbol(std.testing.allocator, NamedSymbol.init("symbol"));
    const symbol_2 = try symbol_table.strToSymbol(std.testing.allocator, NamedSymbol.init("symbol"));
    try std.testing.expectEqual(symbol_1, symbol_2);
}

test "symbol can be converted to str" {
    var symbol_table = SymbolTable{};
    defer symbol_table.deinit(std.testing.allocator);
    const symbol = try symbol_table.strToSymbol(std.testing.allocator, NamedSymbol.init("symbol"));
    const actual = symbol_table.symbolToStr(symbol).?;
    try std.testing.expectEqualDeep(NamedSymbol.init("symbol"), actual);
}
