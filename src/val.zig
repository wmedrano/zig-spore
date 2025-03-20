const std = @import("std");

const Instruction = @import("instruction.zig").Instruction;
const ObjectId = @import("object_manager.zig").ObjectId;
const ObjectManager = @import("object_manager.zig").ObjectManager;
const Vm = @import("vm.zig").Vm;

pub const FunctionError = error{ WrongArity, WrongType } || std.mem.Allocator.Error;

pub const Symbol = packed struct {
    quotes: u2,
    id: u30,

    pub fn eql(self: Symbol, other: Symbol) bool {
        return @as(@bitCast(self), u32) == @as(@bitCast(other), u32);
    }

    pub fn toVal(self: Symbol) Val {
        return Val{ .symbol = self };
    }
};

pub const ListVal = struct {
    list: []Val,

    pub fn garbageCollect(self: *ListVal, allocator: std.mem.Allocator) void {
        if (self.list.len > 0) {
            allocator.free(self.list);
            self.list = &[0]Val{};
        }
    }

    pub fn markChildren(self: *const ListVal, obj: *ObjectManager) void {
        for (self.list) |v| {
            obj.markReachable(v);
        }
    }
};

pub const FunctionVal = struct {
    name: []const u8,
    function: *const fn (*Vm) FunctionError!Val,
};

pub const ByteCodeFunction = struct {
    name: []const u8,
    instructions: []const Instruction,

    pub fn garbageCollect(self: *ByteCodeFunction, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.instructions);
    }

    pub fn markChildren(self: *const ByteCodeFunction, obj: *ObjectManager) void {
        for (self.instructions) |instruction| {
            switch (instruction) {
                .push => |v| obj.markReachable(v),
                .eval => {},
                .deref => {},
                .ret => {},
            }
        }
    }
};

pub const ValTag = enum {
    void,
    bool,
    int,
    float,
    symbol,
    list,
    function,
    bytecode_function,
};

pub const Val = union(ValTag) {
    void,
    bool: bool,
    int: i64,
    float: f64,
    symbol: Symbol,
    list: ObjectId(ListVal),
    function: *const FunctionVal,
    bytecode_function: ObjectId(ByteCodeFunction),
};

test "val is small" {
    try std.testing.expectEqual(2 * @sizeOf(u64), @sizeOf(Val));
}
