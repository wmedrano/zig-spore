const std = @import("std");
const ListVal = @import("val.zig").ListVal;
const SymbolTable = @import("symbol.zig").SymbolTable;
const Val = @import("val.zig").Val;

pub const ObjectManager = struct {
    symbols: SymbolTable = .{},
    lists: ObjectStorage(ListVal) = .{},
    reachable_color: Color = Color.blue,

    pub fn deinit(self: *ObjectManager, allocator: std.mem.Allocator) void {
        self.symbols.deinit(allocator);
        for (self.lists.objects.items) |*list| {
            list.garbageCollect(allocator);
        }
        self.lists.deinit(allocator);
    }

    pub fn putList(self: *ObjectManager, allocator: std.mem.Allocator, list: ListVal) !ObjectId(ListVal) {
        return self.lists.put(allocator, list, self.unreachableColor());
    }

    pub fn markReachable(self: *ObjectManager, val: Val) void {
        switch (val) {
            .void => {},
            .bool => {},
            .int => {},
            .float => {},
            .symbol => {},
            .function => {},
            .list => |list| {
                if (self.lists.color.items[list.idx] == self.reachable_color) {
                    return;
                }
                self.lists.color.items[list.idx] = self.reachable_color;
                for (self.lists.get(list).?.list) |v| {
                    self.markReachable(v);
                }
            },
        }
    }

    pub fn sweepUnreachable(self: *ObjectManager, allocator: std.mem.Allocator) !void {
        try self.lists.sweepColor(self.unreachableColor(), allocator);
    }

    fn unreachableColor(self: *const ObjectManager) Color {
        return otherColor(self.reachable_color);
    }
};

fn ObjectStorage(comptime T: type) type {
    return struct {
        objects: std.ArrayListUnmanaged(T) = .{},
        tags: std.ArrayListUnmanaged(Tag) = .{},
        color: std.ArrayListUnmanaged(Color) = .{},
        available: std.ArrayListUnmanaged(ObjectId(T)) = .{},

        const Self = @This();

        fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            for (self.objects.items, self.color.items) |*obj, color| {
                if (color != Color.tombstone) {
                    obj.garbageCollect(allocator);
                }
            }
            self.objects.deinit(allocator);
            self.tags.deinit(allocator);
            self.color.deinit(allocator);
            self.available.deinit(allocator);
        }

        pub fn put(self: *Self, allocator: std.mem.Allocator, obj: T, color: Color) !ObjectId(T) {
            if (self.available.popOrNull()) |id| {
                self.objects.items[id.idx] = obj;
                self.tags.items[id.idx] = id.tag;
                self.color.items[id.idx] = color;
                return id;
            }
            const id = ObjectId(T){
                .tag = .{},
                .idx = @intCast(self.objects.items.len),
            };
            try self.objects.append(allocator, obj);
            try self.tags.append(allocator, id.tag);
            try self.color.append(allocator, color);
            return id;
        }

        pub fn get(self: *const Self, id: ObjectId(T)) ?*T {
            if (!self.tags.items[id.idx].eql(id.tag)) {
                return null;
            }
            return &self.objects.items[id.idx];
        }

        pub fn sweepColor(self: *Self, sweep_color: Color, allocator: std.mem.Allocator) !void {
            for (self.color.items, 0..self.color.items.len) |color, idx| {
                if (color == sweep_color) {
                    self.objects.items[idx].garbageCollect(allocator);
                    self.color.items[idx] = Color.tombstone;
                    self.tags.items[idx] = self.tags.items[idx].next();
                    try self.available.append(
                        allocator,
                        ObjectId(T){
                            .tag = self.tags.items[idx],
                            .idx = @intCast(idx),
                        },
                    );
                }
            }
        }
    };
}

const Color = enum { blue, red, tombstone };

fn otherColor(c: Color) Color {
    switch (c) {
        .blue => return Color.red,
        .red => return Color.blue,
        .tombstone => return Color.tombstone,
    }
}

const Tag = packed struct {
    id: u8 = 0,
    pub fn next(self: Tag) Tag {
        return Tag{ .id = self.id +% 1 };
    }

    pub fn eql(self: Tag, other: Tag) bool {
        return self.id == other.id;
    }
};

pub fn ObjectId(comptime _: type) type {
    return packed struct {
        tag: Tag,
        idx: u24,
    };
}
