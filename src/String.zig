const std = @import("std");

const ObjectManager = @import("ObjectManager.zig");
const String = @This();

string: []const u8,

/// Free any memory associated with the `String`.
pub fn garbageCollect(self: *String, allocator: std.mem.Allocator) void {
    if (self.string.len > 0) {
        allocator.free(self.string);
    }
    self.string = "";
}

/// Strings don't have children values, but this function is required
/// by `ObjectManager`.
pub fn markChildren(_: String, _: ObjectManager.Marker) void {}
