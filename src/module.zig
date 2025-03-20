const std = @import("std");

const Symbol = @import("val.zig").Symbol;
const Val = @import("val.zig").Val;

pub const Module = struct {
    values: std.AutoHashMapUnmanaged(Symbol, Val) = .{},

    pub fn deinit(self: *Module, allocator: std.mem.Allocator) void {
        self.values.deinit(allocator);
    }

    pub fn putValue(self: *Module, allocator: std.mem.Allocator, symbol: Symbol, value: Val) !void {
        try self.values.put(allocator, symbol, value);
    }

    pub fn getValue(self: *const Module, symbol: Symbol) ?Val {
        return self.values.get(symbol);
    }
};
