const std = @import("std");

const ObjectManager = @import("ObjectManager.zig");
const Val = @import("Val.zig");

const List = @This();

list: []Val,

pub fn garbageCollect(self: *List, allocator: std.mem.Allocator) void {
    if (self.list.len > 0) {
        allocator.free(self.list);
        self.list = &.{};
    }
}

pub fn markChildren(self: List, obj: *ObjectManager) void {
    for (self.list) |v| {
        obj.markReachable(v);
    }
}
