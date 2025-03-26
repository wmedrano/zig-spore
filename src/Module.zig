const std = @import("std");

const InternedSymbol = @import("val.zig").InternedSymbol;
const Val = @import("val.zig").Val;

const Module = @This();

values: std.AutoHashMapUnmanaged(InternedSymbol, Val) = .{},

pub fn deinit(self: *Module, allocator: std.mem.Allocator) void {
    self.values.deinit(allocator);
}

pub fn putValue(self: *Module, allocator: std.mem.Allocator, symbol: InternedSymbol, value: Val) !void {
    try self.values.put(allocator, symbol, value);
}

pub fn getValue(self: Module, symbol: InternedSymbol) ?Val {
    return self.values.get(symbol);
}
