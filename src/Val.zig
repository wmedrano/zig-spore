const std = @import("std");

const Instruction = @import("instruction.zig").Instruction;
const ObjectManager = @import("ObjectManager.zig");
const Vm = @import("Vm.zig");
const Symbol = @import("Symbol.zig");

const Val = @This();

repr: ValRepr,

pub const FunctionError = error{ WrongArity, WrongType } || std.mem.Allocator.Error;

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

const ValRepr = union(ValTag) {
    void,
    bool: bool,
    int: i64,
    float: f64,
    symbol: InternedSymbol,
    list: ObjectManager.Id(List),
    function: *const FunctionVal,
    bytecode_function: ObjectManager.Id(ByteCodeFunction),
};

/// Initialize a new `Val` to the default `void` value.
pub fn init() Val {
    return .{ .repr = .{ .void = {} } };
}

pub fn fromList(vm: *Vm, list: []const Val) !Val {
    const cloned_list = try vm.allocator().dupe(Val, list);
    return Val.fromOwnedList(vm, cloned_list);
}

pub fn fromOwnedList(vm: *Vm, list: []Val) !Val {
    const id = try vm.env.objects.put(List, vm.allocator(), .{ .list = list });
    return .{ .repr = .{ .list = id } };
}

pub fn fromBool(b: bool) Val {
    return .{ .repr = .{ .bool = b } };
}

pub fn fromInt(i: i64) Val {
    return .{ .repr = .{ .int = i } };
}

pub fn fromFloat(f: f64) Val {
    return .{ .repr = .{ .float = f } };
}

pub fn fromInternedSymbol(s: InternedSymbol) Val {
    return .{ .repr = .{ .symbol = s } };
}

pub fn asInternedSymbol(self: Val) ?InternedSymbol {
    switch (self.repr) {
        .symbol => |symbol| return symbol,
        else => return null,
    }
}

pub fn asInt(self: Val) ?i64 {
    switch (self.repr) {
        .int => |x| return x,
        else => return null,
    }
}

pub fn asFloat(self: Val) ?f64 {
    switch (self.repr) {
        .float => |x| return x,
        else => return null,
    }
}

pub fn asSymbol(self: Val, vm: Vm) !?Symbol {
    const symbol = self.asInternedSymbol();
    if (!symbol) return null;
    vm.env.objects.symbols.symbolToStr(symbol.?);
}

pub fn asList(self: Val, vm: Vm) ?List {
    switch (self.repr) {
        .list => |id| {
            const list = if (vm.env.objects.get(List, id)) |list| list else return null;
            return list.*;
        },
        else => return null,
    }
}

pub const InternedSymbol = packed struct {
    quotes: u2,
    id: u30,

    pub fn eql(self: InternedSymbol, other: InternedSymbol) bool {
        return self.quotes == other.quotes and self.id == other.id;
    }

    pub fn toVal(self: InternedSymbol) Val {
        return Val.fromInternedSymbol(self);
    }

    pub fn quoted(self: InternedSymbol) InternedSymbol {
        if (self.quotes == std.math.maxInt(u2)) return self;
        return InternedSymbol{
            .quotes = self.quotes + 1,
            .id = self.id,
        };
    }

    pub fn unquoted(self: InternedSymbol) InternedSymbol {
        if (self.quotes == 0) return self;
        return InternedSymbol{
            .quotes = self.quotes - 1,
            .id = self.id,
        };
    }
};

pub const List = struct {
    list: []Val,

    pub fn garbageCollect(self: *List, allocator: std.mem.Allocator) void {
        if (self.list.len > 0) {
            allocator.free(self.list);
            self.list = &[0]Val{};
        }
    }

    pub fn markChildren(self: List, obj: *ObjectManager) void {
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

    pub fn markChildren(self: ByteCodeFunction, obj: *ObjectManager) void {
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

test "val is small" {
    try std.testing.expectEqual(2 * @sizeOf(u64), @sizeOf(Val));
}
