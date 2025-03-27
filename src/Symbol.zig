const std = @import("std");
const StringInterner = @import("StringInterner.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

const Symbol = @This();

quotes: u2,
name: []const u8,

pub fn fromStr(str: []const u8) !Symbol {
    var quotes: usize = 0;
    while (quotes < str.len and str[quotes] == '\'') {
        quotes += 1;
    }
    if (quotes > std.math.maxInt(u2)) {
        return error.TooManyQuotes;
    }
    const name = str[quotes..];
    if (name.len == 0) return error.EmptySymbol;
    return Symbol{
        .quotes = @intCast(quotes),
        .name = name,
    };
}

pub fn intern(self: Symbol, vm: *Vm) !Interned {
    const id = try vm.objects.string_interner.intern(
        vm.allocator(),
        self.name,
    );
    return .{ .quotes = self.quotes, .id = id };
}

pub fn format(
    self: Symbol,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    switch (self.quotes) {
        0 => try writer.print("{s}", .{self.name}),
        1 => try writer.print("'{s}", .{self.name}),
        2 => try writer.print("''{s}", .{self.name}),
        3 => try writer.print("'''{s}", .{self.name}),
    }
}

pub const InternedKey = packed struct {
    _: u2,
    id: StringInterner.Id,

    pub fn fromKey(vm: *Vm, key: Key) !InternedKey {
        const id = try vm.objects.string_interner.intern(
            vm.allocator(),
            key.name,
        );
        return .{ ._ = 0, .id = id };
    }

    pub fn toKey(self: InternedKey, vm: *const Vm) ?Key {
        const str = if (vm.objects.string_interner.getString(self.id)) |s| s else return null;
        return .{ .name = str };
    }

    pub fn toVal(self: InternedKey) Val {
        return .{ .repr = .{ .key = self } };
    }
};

test "interned key size is small" {
    try std.testing.expectEqual(4, @sizeOf(InternedKey));
}

pub const Key = struct {
    name: []const u8,

    pub fn format(
        self: Key,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print(":{s}", .{self.name});
    }
};

pub const Interned = packed struct {
    quotes: u2,
    id: StringInterner.Id,

    pub fn eql(self: Interned, other: Interned) bool {
        return self.quotes == other.quotes and self.id.eql(other.id);
    }

    pub fn toVal(self: Interned) Val {
        return .{ .repr = .{ .symbol = self } };
    }

    pub fn toSymbol(self: Interned, vm: *const Vm) ?Symbol {
        const maybe_str = if (vm.objects.string_interner.getString(self.id)) |s| s else return null;
        return .{ .quotes = self.quotes, .name = maybe_str };
    }

    pub fn quoted(self: Interned) Interned {
        if (self.quotes == std.math.maxInt(u2)) return self;
        return Interned{
            .quotes = self.quotes + 1,
            .id = self.id,
        };
    }

    pub fn unquoted(self: Interned) Interned {
        if (self.quotes == 0) return self;
        return Interned{
            .quotes = self.quotes - 1,
            .id = self.id,
        };
    }
};

test "interned symbol size is small" {
    try std.testing.expectEqual(4, @sizeOf(Interned));
}
