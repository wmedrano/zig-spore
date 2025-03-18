const std = @import("std");
const ListVal = @import("val.zig").ListVal;
const SymbolTable = @import("symbol.zig").SymbolTable;

pub const ObjectManager = struct {
    symbols: SymbolTable = .{},
    lists: ObjectStorage(ListVal) = .{},

    pub fn deinit(self: *ObjectManager, allocator: std.mem.Allocator) void {
        self.symbols.deinit(allocator);
        for (self.lists.objects.items) |list_slot| {
            allocator.free(list_slot.list);
        }
        self.lists.deinit(allocator);
    }
};

fn ObjectStorage(comptime T: type) type {
    return struct {
        // Stores all objects. Objects may be referenced by index.
        objects: std.ArrayListUnmanaged(T) = .{},
        // Stores a tag. tags[idx] contains the tag for objects[idx]. A tag is
	// assigned to each object to make sure that it is not referenced after
	// garbage collection.
        tags: std.ArrayListUnmanaged(Tag) = .{},
	// Contains all indices that are available.
        available: std.ArrayListUnmanaged(ObjectId(T)) = .{},

        const Self = @This();

	pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.objects.deinit(allocator);
            self.tags.deinit(allocator);
            self.available.deinit(allocator);
        }

        pub fn put(self: *Self, allocator: std.mem.Allocator, obj: T) !ObjectId(T) {
            if (self.available.popOrNull()) |old_id| {
                const id = ObjectId(T){
                    .tag = old_id.tag.next(),
                    .idx = old_id.idx,
                };
                self.objects.items[id.idx] = obj;
                self.tags.items[id.idx] = id.tag;
                return id;
            }
            const id = ObjectId(T){
                .tag = .{},
                .idx = @intCast(self.objects.items.len),
            };
            try self.objects.append(allocator, obj);
            try self.tags.append(allocator, id.tag);
            return id;
        }

        pub fn get(self: *const Self, id: ObjectId(T)) ?*T {
            if (!self.tags.items[id.idx].eql(id.tag)) {
                return null;
            }
            return &self.objects.items[id.idx];
        }
    };
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
