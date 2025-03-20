const std = @import("std");

const ByteCodeFunction = @import("val.zig").ByteCodeFunction;
const ListVal = @import("val.zig").ListVal;
const SymbolTable = @import("symbol.zig").SymbolTable;
const Val = @import("val.zig").Val;

pub const ObjectManager = struct {
    symbols: SymbolTable = .{},
    lists: ObjectStorage(ListVal) = .{},
    bytecode_functions: ObjectStorage(ByteCodeFunction) = .{},
    reachable_color: Color = Color.blue,

    pub fn deinit(self: *ObjectManager, allocator: std.mem.Allocator) void {
        self.symbols.deinit(allocator);
        self.lists.deinit(allocator);
        self.bytecode_functions.deinit(allocator);
    }

    pub fn put(self: *ObjectManager, comptime T: type, allocator: std.mem.Allocator, val: T) !ObjectId(T) {
        var object_storage = switch (T) {
            ListVal => &self.lists,
            ByteCodeFunction => &self.bytecode_functions,
            else => @compileError("type not supported"),
        };
        return object_storage.put(allocator, val, self.unreachableColor());
    }

    pub fn get(self: *const ObjectManager, comptime T: type, id: ObjectId(T)) ?*T {
        const object_storage = switch (T) {
            ListVal => self.lists,
            ByteCodeFunction => self.bytecode_functions,
            else => @compileError("type not supported"),
        };
        return object_storage.get(id);
    }

    pub fn markReachable(self: *ObjectManager, val: Val) void {
        switch (val) {
            .void => {},
            .bool => {},
            .int => {},
            .float => {},
            .symbol => {},
            .function => {},
            .list => |id| self.lists.markReachable(id, self),
            .bytecode_function => |id| self.bytecode_functions.markReachable(id, self),
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

        pub fn markReachable(self: *Self, id: ObjectId(T), objects: *ObjectManager) void {
            if (self.color.items[id.idx] != objects.reachable_color) {
                self.color.items[id.idx] = objects.reachable_color;
                if (self.get(id)) |v| {
                    v.markChildren(objects);
                }
            }
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

pub fn ObjectId(comptime T: type) type {
    return packed struct {
        tag: Tag,
        idx: u24,

        const Self = @This();
        pub fn toVal(self: Self) Val {
            switch (T) {
                ListVal => return Val{ .list = self },
                else => @compileError("no valid conversion to Val"),
            }
        }
    };
}
