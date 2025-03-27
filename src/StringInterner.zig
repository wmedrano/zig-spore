const std = @import("std");

const Val = @import("Val.zig");

const StringInterner = @This();

/// An array where each index is the id of the string stored on
/// that slot.
strings: std.ArrayListUnmanaged([]const u8) = .{},

/// Maps from string to its id.
string_to_id: std.StringHashMapUnmanaged(u30) = .{},

pub const Id = packed struct {
    id: u30,

    pub fn eql(self: Id, other: Id) bool {
        return self.id == other.id;
    }
};

pub fn deinit(self: *StringInterner, allocator: std.mem.Allocator) void {
    for (self.strings.items) |k| {
        allocator.free(k);
    }
    self.strings.deinit(allocator);
    self.string_to_id.deinit(allocator);
}

pub fn intern(self: *StringInterner, allocator: std.mem.Allocator, str: []const u8) !Id {
    if (self.string_to_id.get(str)) |id| {
        return .{ .id = id };
    }
    const owned_str = try allocator.dupe(u8, str);
    const id: u30 = @intCast(self.size());
    try self.strings.append(allocator, owned_str);
    try self.string_to_id.put(allocator, owned_str, id);
    return .{ .id = id };
}

pub fn getString(self: StringInterner, id: Id) ?[]const u8 {
    if (id.id < self.size()) {
        return self.strings.items[id.id];
    }
    return null;
}

fn size(self: StringInterner) u32 {
    return @intCast(self.strings.items.len);
}
