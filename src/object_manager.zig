const std = @import("std");
const ListVal = @import("val.zig").ListVal;
const SymbolTable = @import("symbol.zig").SymbolTable;

pub const ObjectManager = struct {
    symbols: SymbolTable = .{},
    lists: ObjectStorage(ListVal) = .{},

    pub fn deinit(self: *ObjectManager, allocator: std.mem.Allocator) void {
        self.symbols.deinit(allocator);
        for (self.lists.objects.items) |list_slot| {
            allocator.free(list_slot.obj.list);
        }
        self.lists.deinit(allocator);
    }
};

fn ObjectStorage(comptime T: type) type {
    return struct {
        objects: std.ArrayListUnmanaged(TaggedObject(T)) = .{},
        available: std.ArrayListUnmanaged(ObjectId(T)) = .{},
        const Self = @This();
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.objects.deinit(allocator);
            self.available.deinit(allocator);
        }

        pub fn put(self: *Self, allocator: std.mem.Allocator, obj: T) !ObjectId(T) {
            if (self.available.popOrNull()) |old_id| {
                const id = ObjectId(T){
                    .tag = old_id.tag +% 1,
                    .idx = old_id.idx,
                };
                self.objects.items[id.idx] = TaggedObject(T){
                    .obj = obj,
                    .tag = id.tag,
                };
                return id;
            }
            const id = ObjectId(T){
                .tag = 0,
                .idx = @intCast(self.objects.items.len),
            };
            try self.objects.append(allocator, TaggedObject(T){
                .obj = obj,
                .tag = id.tag,
            });
            return id;
        }

        pub fn get(self: *const Self, id: ObjectId(T)) ?*T {
            if (self.objects.items[id.idx].tag != id.tag) {
                return null;
            }
            return &self.objects.items[id.idx].obj;
        }
    };
}

fn TaggedObject(comptime T: type) type {
    return struct {
        obj: T,
        tag: u8,
    };
}

pub fn ObjectId(comptime _: type) type {
    return packed struct {
        tag: u8,
        idx: u24,
    };
}
