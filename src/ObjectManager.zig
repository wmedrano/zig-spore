const std = @import("std");

const ByteCodeFunction = Val.ByteCodeFunction;
const Error = @import("root.zig").Error;
const List = @import("List.zig");
const ObjectManager = @This();
const String = @import("String.zig");
const StringInterner = @import("StringInterner.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

string_interner: StringInterner = .{},
strings: ObjectStorage(String) = .{},
lists: ObjectStorage(List) = .{},
bytecode_functions: ObjectStorage(ByteCodeFunction) = .{},
reachable_color: Color = Color.blue,

/// Free all allocated objects.
pub fn deinit(self: *ObjectManager, allocator: std.mem.Allocator) void {
    self.string_interner.deinit(allocator);
    self.strings.deinit(allocator);
    self.lists.deinit(allocator);
    self.bytecode_functions.deinit(allocator);
}

/// Run the garbage collector.
pub fn runGc(self: *ObjectManager, vm: *Vm, external: []const Val) !void {
    self.marker().markReachableMany(external);
    self.marker().markReachableMany(vm.stack.items);
    for (vm.stack.frames.items) |stack_frame| {
        ByteCodeFunction.markInstructions(stack_frame.instructions, self.marker());
    }
    var globalsIter = vm.global.values.valueIterator();
    while (globalsIter.next()) |v| {
        self.marker().markReachable(v.*);
    }
    try self.sweepUnreachable(vm.allocator());
}

/// Store an object of type `T` and gets its `Id` handle.
pub fn put(self: *ObjectManager, comptime T: type, allocator: std.mem.Allocator, val: T) !Id(T) {
    var object_storage = switch (T) {
        String => &self.strings,
        List => &self.lists,
        ByteCodeFunction => &self.bytecode_functions,
        else => @compileError("type not supported"),
    };
    return object_storage.put(allocator, val, self.unreachableColor());
}

/// Get an object with the given `Id` handle or `null` if it is not
/// found.
pub fn get(self: ObjectManager, comptime T: type, id: Id(T)) ?*T {
    const object_storage = switch (T) {
        String => self.strings,
        List => self.lists,
        ByteCodeFunction => self.bytecode_functions,
        else => @compileError("type not supported"),
    };
    return object_storage.get(id);
}

/// `Marker` is used to mark objects as being used.
pub const Marker = struct {
    object_manager: *ObjectManager,

    /// Mark a single value as reachable. This prevents the `val` from
    /// being collected during the next garbage collector run.
    pub fn markReachable(self: Marker, val: Val) void {
        switch (val._repr) {
            .void, .bool, .int, .float, .symbol, .key, .function => {},
            .string => |id| self.object_manager.strings.markReachable(id, self),
            .list => |id| self.object_manager.lists.markReachable(id, self),
            .bytecode_function => |id| self.object_manager.bytecode_functions.markReachable(id, self),
        }
    }

    /// Mark many values as reachable. Similar to `markReachable` but
    /// takes many values at once.
    pub fn markReachableMany(self: Marker, vals: []const Val) void {
        for (vals) |v| self.markReachable(v);
    }
};

fn marker(self: *ObjectManager) Marker {
    return .{ .object_manager = self };
}

fn sweepUnreachable(self: *ObjectManager, allocator: std.mem.Allocator) !void {
    try self.strings.sweepColor(self.unreachableColor(), allocator);
    try self.lists.sweepColor(self.unreachableColor(), allocator);
    try self.bytecode_functions.sweepColor(self.unreachableColor(), allocator);
}

fn unreachableColor(self: *ObjectManager) Color {
    return otherColor(self.reachable_color);
}

fn ObjectStorage(comptime T: type) type {
    return struct {
        objects: std.ArrayListUnmanaged(T) = .{},
        tags: std.ArrayListUnmanaged(Tag) = .{},
        color: std.ArrayListUnmanaged(Color) = .{},
        available: std.ArrayListUnmanaged(Id(T)) = .{},

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

        pub fn put(self: *Self, allocator: std.mem.Allocator, obj: T, color: Color) !Id(T) {
            if (self.available.popOrNull()) |id| {
                self.objects.items[id.idx] = obj;
                self.tags.items[id.idx] = id.tag;
                self.color.items[id.idx] = color;
                return id;
            }
            const id = Id(T){
                .tag = .{},
                .idx = @intCast(self.objects.items.len),
            };
            try self.objects.append(allocator, obj);
            errdefer _ = self.objects.popOrNull();
            try self.tags.append(allocator, id.tag);
            errdefer _ = self.tags.popOrNull();
            try self.color.append(allocator, color);
            errdefer _ = self.color.popOrNull();
            return id;
        }

        pub fn get(self: Self, id: Id(T)) ?*T {
            if (!self.tags.items[id.idx].eql(id.tag)) {
                return null;
            }
            return &self.objects.items[id.idx];
        }

        pub fn markReachable(self: *Self, id: Id(T), m: ObjectManager.Marker) void {
            if (self.color.items[id.idx] != m.object_manager.reachable_color) {
                self.color.items[id.idx] = m.object_manager.reachable_color;
                if (self.get(id)) |v| v.markChildren(m);
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
                        Id(T){
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

pub fn Id(comptime T: type) type {
    return packed struct {
        tag: Tag,
        idx: u24,

        const Self = @This();
        pub fn toVal(self: Self) Val {
            switch (T) {
                String => return Val{ ._repr = .{ .string = self } },
                List => return Val{ ._repr = .{ .list = self } },
                ByteCodeFunction => return Val{ ._repr = .{ .bytecode_function = self } },
                else => @compileError("no valid conversion to Val"),
            }
        }
    };
}

test "garbage collector removes unused val" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    // Before GC
    const gc_val = try vm.evalStr(Val, @as([]const u8, "\"hello world\""));
    try std.testing.expectEqualStrings(
        "hello world",
        try gc_val.toZig([]const u8, &vm),
    );

    // After GC
    try vm.runGc(&.{});
    try std.testing.expectError(
        Error.ObjectNotFound,
        gc_val.toZig([]const u8, &vm),
    );
}

test "garbage collector keeps external value" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    // Before GC
    const keep_val = try vm.evalStr(Val, @as([]const u8, "\"hello world\""));
    try std.testing.expectEqualStrings(
        "hello world",
        try keep_val.toZig([]const u8, &vm),
    );

    // After GC
    try vm.runGc(&.{keep_val});
    try std.testing.expectEqualStrings(
        "hello world",
        try keep_val.toZig([]const u8, &vm),
    );
}

test "garbage collector keeps global value" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    // Before GC
    const global_val = try vm.evalStr(Val, @as([]const u8, "\"hello world\""));
    try vm.global.registerValueByName(&vm, "global-value", global_val);
    try std.testing.expectEqualStrings(
        "hello world",
        try vm.evalStr([]const u8, "global-value"),
    );

    // After GC
    try vm.runGc(&.{});
    try std.testing.expectEqualStrings(
        "hello world",
        try global_val.toZig([]const u8, &vm),
    );
}

test "referenced bytecode values are not garbage collected" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    // Before GC
    _ = try vm.evalStr(Val, "(defun magic-string () \"hello world\")");
    const referenced_val = try vm.evalStr(Val, "(magic-string)");
    try std.testing.expectFmt(
        "\"hello world\"",
        "{any}",
        .{referenced_val.formatted(&vm)},
    );

    // After GC
    try vm.runGc(&.{});
    try std.testing.expectFmt(
        "\"hello world\"",
        "{any}",
        .{referenced_val.formatted(&vm)},
    );
}

test "referenced list values are not garbage collected" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    // Before GC
    _ = try vm.evalStr(Val, "(def magic-strings (list \"hello\" \"world\"))");
    const referenced_val = vm.global.getValueByName(&vm, "magic-strings").?;
    try std.testing.expectFmt(
        "(\"hello\" \"world\")",
        "{any}",
        .{referenced_val.formatted(&vm)},
    );

    // After GC
    try vm.runGc(&.{});
    try std.testing.expectFmt(
        "(\"hello\" \"world\")",
        "{any}",
        .{referenced_val.formatted(&vm)},
    );
}
