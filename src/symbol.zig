const std = @import("std");

pub const Symbol = struct {
    id: u32,
};

pub const SymbolTable = struct {
    symbols: std.ArrayListUnmanaged([]const u8) = .{},
    name_to_symbol: std.StringHashMapUnmanaged(Symbol) = .{},

    pub fn deinit(self: *SymbolTable, allocator: std.mem.Allocator) void {
        for (self.symbols.items) |k| {
            allocator.free(k);
        }
        self.symbols.deinit(allocator);
        self.name_to_symbol.deinit(allocator);
    }

    pub fn strToSymbol(self: *SymbolTable, allocator: std.mem.Allocator, str: []const u8) !Symbol {
        if (self.name_to_symbol.get(str)) |v| {
            return v;
        }
        const name = try allocator.dupe(u8, str);
        const id = Symbol{ .id = self.size() };
        try self.symbols.append(allocator, name);
        try self.name_to_symbol.put(allocator, name, id);
        return id;
    }

    pub fn symbolToStr(self: *const SymbolTable, symbol: Symbol) ?[]const u8 {
        if (symbol.id < self.size()) {
            return self.symbols.items[symbol.id];
        }
        return null;
    }

    fn size(self: *const SymbolTable) u32 {
        return @intCast(self.symbols.items.len);
    }
};

test "symbol is 32bits" {
    try std.testing.expectEqual(32, @bitSizeOf(Symbol));
}

test "symbols from different but equivalent strings are bitwise equal" {
    var symbol_table = SymbolTable{};
    defer symbol_table.deinit(std.testing.allocator);
    const symbol_1 = try symbol_table.strToSymbol(std.testing.allocator, "symbol");
    const symbol_2 = try symbol_table.strToSymbol(std.testing.allocator, "symbol");
    try std.testing.expectEqual(symbol_1, symbol_2);
}

test "symbol can be converted to str" {
    var symbol_table = SymbolTable{};
    defer symbol_table.deinit(std.testing.allocator);
    const symbol = try symbol_table.strToSymbol(std.testing.allocator, "symbol");
    const actual = symbol_table.symbolToStr(symbol).?;
    try std.testing.expectEqualStrings("symbol", actual);
}
