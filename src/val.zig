const std = @import("std");

const Symbol = @import("symbol.zig").Symbol;
const ObjectId = @import("object_manager.zig").ObjectId;
const Vm = @import("vm.zig").Vm;

pub const FunctionError = error{ WrongArity, WrongType } || std.mem.Allocator.Error;

pub const ListVal = struct {
    list: []Val,
};

pub const FunctionVal = struct {
    name: []const u8,
    function: *const fn (*Vm) FunctionError!Val,
};

pub const ValTag = enum {
    void,
    bool,
    int,
    float,
    symbol,
    list,
    function,
};

pub const Val = union(ValTag) {
    void,
    bool: bool,
    int: i64,
    float: f64,
    symbol: Symbol,
    list: ObjectId(ListVal),
    function: *const FunctionVal,
};
