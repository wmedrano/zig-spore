const std = @import("std");

const String = @This();
const ObjectManager = @import("ObjectManager.zig");

string: []const u8,

pub fn garbageCollect(self: *String, allocator: std.mem.Allocator) void {
    if (self.string.len > 0) {
        allocator.free(self.string);
    }
    self.string = "";
}

pub fn markChildren(_: String, _: *ObjectManager) void {}
