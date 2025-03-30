const std = @import("std");

const Instruction = @import("instruction.zig").Instruction;
const ObjectManager = @import("ObjectManager.zig");
const StringInterner = @import("StringInterner.zig");
const Symbol = @import("Symbol.zig");
const Vm = @import("Vm.zig");
const function = @import("function.zig");

const Val = @This();

repr: ValRepr,

pub const ValTag = enum {
    void,
    bool,
    int,
    float,
    string,
    symbol,
    key,
    list,
    function,
    bytecode_function,
};

const ValRepr = union(ValTag) {
    void,
    bool: bool,
    int: i64,
    float: f64,
    string: ObjectManager.Id(String),
    symbol: Symbol.Interned,
    key: Symbol.InternedKey,
    list: ObjectManager.Id(List),
    function: *const function.FunctionVal,
    bytecode_function: ObjectManager.Id(function.ByteCodeFunction),
};

/// Initialize a new `Val` to the default `void` value.
pub fn init() Val {
    return .{ .repr = .{ .void = {} } };
}

/// Convert from a Zig value to a Spore `Val`.
///
/// Supported Types:
/// - `Val` - Returns `val` as is.
/// - `void` - Converts to a `Val.void`.
/// - `bool` - Converts to a `Val.bool`.
/// - `i64` - Converts to a `Val.int`.
/// - `f64` - Converts to a `Val.float`.
/// - `[]const u8` or `[]u8` - Creates a new `Val.string` by copying the slice
///     contents.
/// - `Symbol` - Converts to a `Val.symbol`.
/// - `Symbol.Interned` - Converts to a `Val.symbol`.
/// - `[]const Val` or `[]Val` - Converts to a `Val.list`.
pub fn fromZig(vm: *Vm, val: anytype) !Val {
    const T = @TypeOf(val);
    if (T == Val) return val;
    switch (T) {
        void => return init(),
        bool => return .{ .repr = .{ .bool = val } },
        i64 => return .{ .repr = .{ .int = val } },
        f64 => return .{ .repr = .{ .float = val } },
        []const u8, []u8 => {
            const owned_string = try vm.allocator().dupe(u8, val);
            const id = try vm.objects.put(String, vm.allocator(), .{ .string = owned_string });
            return .{ .repr = .{ .string = id } };
        },
        Symbol => {
            const interned_symbol = try val.intern(vm);
            return interned_symbol.toVal();
        },
        Symbol.Interned => return val.toVal(),
        Symbol.Key => {
            const interned_key = try Symbol.InternedKey.fromKey(vm, val);
            return interned_key.toVal();
        },
        Symbol.InternedKey => return val.toVal(),
        []const Val, []Val => {
            const owned_list = try vm.allocator().dupe(Val, val);
            return fromOwnedList(vm, owned_list);
        },
        else => @compileError("fromZig not supported for type " ++ @typeName(T)),
    }
}

pub const ToZigError = error{
    WrongType,
    ObjectNotFound,
};

/// Convert from a Spore `Val` to a Zig value.
///
/// Supported Types `T`:
/// - `void`
/// - `bool`
/// - `i64`
/// - `f64`
/// - `[]const u8` (returns a slice pointing to the Val's internal string)
/// - `Symbol` or `Symbol.Interned`
/// - `Symbol.Key` or `InternedKey`
/// - `[]const Val` (returns a slice pointing to the Val's internal list)
///
/// Note: For slice types (`[]const u8`, `[]const Val`), the returned slice's
/// lifetime is tied to the underlying object in the Vm's ObjectManager.
/// The caller must ensure the Vm and its objects outlive the use of the slice.
pub fn toZig(self: Val, comptime T: type, vm: *const Vm) ToZigError!T {
    if (T == Val) return self;
    switch (self.repr) {
        .void => {
            if (T == void) return;
            return ToZigError.WrongType;
        },
        .bool => |v| {
            if (T == bool) return v;
            return ToZigError.WrongType;
        },
        .int => |v| {
            if (T == i64) return v;
            return ToZigError.WrongType;
        },
        .float => |v| {
            if (T == f64) return v;
            return ToZigError.WrongType;
        },
        .string => {
            if (T == []const u8) {
                if (self.asString(vm)) |s| {
                    return s;
                }
            }
            return ToZigError.WrongType;
        },
        .symbol => |interned_symbol| {
            switch (T) {
                Symbol.Interned => return interned_symbol,
                Symbol => {
                    const maybe_str = vm.objects.string_interner.getString(interned_symbol.id);
                    if (maybe_str) |str| {
                        return .{ .quotes = interned_symbol.quotes, .name = str };
                    }
                    return ToZigError.ObjectNotFound;
                },
                else => return ToZigError.WrongType,
            }
        },
        .key => |interned_key| {
            switch (T) {
                Symbol.InternedKey => return interned_key,
                Symbol.Key => {
                    const maybe_key = vm.objects.symbols.internedSymbolToSymbol(interned_key.repr);
                    if (maybe_key) |k| {
                        return Symbol.Key{ .name = k.name };
                    }
                    return ToZigError.ObjectNotFound;
                },
                else => return ToZigError.WrongType,
            }
        },
        .list => {
            switch (T) {
                []const Val => {
                    if (self.asList(vm)) |l| {
                        return l;
                    }
                    return ToZigError.ObjectNotFound;
                },
                else => return ToZigError.WrongType,
            }
        },
        // Types not generally convertible back to simple Zig types.
        .function, .bytecode_function => return ToZigError.WrongType,
    }
}

/// Returns `true` if `self` is truthy.
///
/// All values are truthy except for `void` and `false`.
pub fn isTruthy(self: Val) bool {
    return switch (self.repr) {
        .void => false,
        .bool => |b| b,
        else => true,
    };
}

pub fn fromOwnedList(vm: *Vm, owned_list: []Val) !Val {
    const id = try vm.objects.put(List, vm.allocator(), .{ .list = owned_list });
    return .{ .repr = .{ .list = id } };
}

pub fn fromSymbolStr(vm: *Vm, symbol_str: []const u8) !Val {
    const symbol = try Symbol.fromStr(symbol_str);
    return Val.fromZig(vm, symbol);
}

pub fn asInternedSymbol(self: Val) ?Symbol.Interned {
    switch (self.repr) {
        .symbol => |symbol| return symbol,
        else => return null,
    }
}

pub fn asInternedKey(self: Val) ?Symbol.InternedKey {
    switch (self.repr) {
        .key => |k| return k,
        else => return null,
    }
}

/// Returns true if `Val` is a number.
pub fn isNumber(self: Val) bool {
    switch (self.repr) {
        .int => return true,
        .float => return true,
        else => return false,
    }
}

/// Returns true if `Val` is an int.
pub fn isInt(self: Val) bool {
    switch (self.repr) {
        .int => return true,
        else => return false,
    }
}

fn asString(self: Val, vm: *const Vm) ?[]const u8 {
    switch (self.repr) {
        .string => |id| {
            const string = if (vm.objects.get(String, id)) |string| string else return null;
            return string.string;
        },
        else => return null,
    }
}

fn asSymbol(self: Val, vm: *const Vm) !?Symbol {
    const interned_symbol = if (self.asInternedSymbol()) |s| s else return null;
    return interned_symbol.toSymbol(vm);
}

fn asKey(self: Val, vm: *const Vm) !?Symbol.Key {
    const interned_key = if (self.asInternedKey()) |k| k else return null;
    return interned_key.toKey(vm);
}

fn asList(self: Val, vm: *const Vm) ?[]const Val {
    switch (self.repr) {
        .list => |id| {
            const list = if (vm.objects.get(List, id)) |list| list else return null;
            return list.list;
        },
        else => return null,
    }
}

/// Get a struct that can format `Val`.
pub fn formatted(self: Val, vm: *const Vm) FormattedVal {
    return FormattedVal{ .val = self, .vm = vm };
}

const FormattedVal = struct {
    val: Val,
    vm: *const Vm,

    pub fn format(
        self: FormattedVal,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self.val.repr) {
            .void => try writer.print("<void>", .{}),
            .bool => |x| try writer.print("{any}", .{x}),
            .int => |x| try writer.print("{any}", .{x}),
            .float => |x| try writer.print("{any}", .{x}),
            .string => {
                const string = try self.val.toZig([]const u8, self.vm);
                try writer.print("\"{s}\"", .{string});
            },
            .symbol => |interned_symbol| {
                if (try self.val.asSymbol(self.vm)) |s| {
                    try writer.print("{any}", .{s});
                } else {
                    try writer.print("{any}", .{Symbol{ .quotes = interned_symbol.quotes, .name = "" }});
                }
            },
            .key => if (try self.val.asKey(self.vm)) |k| {
                try writer.print("{any}", .{k});
            } else {
                try writer.print("{any}", .{Symbol.Key{ .name = "" }});
            },
            .list => {
                const list = self.val.asList(self.vm).?;
                try writer.print("(", .{});
                for (list, 0..list.len) |v, idx| {
                    if (idx == 0) {
                        try writer.print("{any}", .{v.formatted(self.vm)});
                    } else {
                        try writer.print(" {any}", .{v.formatted(self.vm)});
                    }
                }
                try writer.print(")", .{});
            },
            .function => |f| {
                try writer.print("(native-function {s})", .{f.name});
            },
            .bytecode_function => |id| {
                const f = self.vm.objects.get(function.ByteCodeFunction, id).?;
                try writer.print("(function {s})", .{f.name});
            },
        }
    }
};

pub const String = struct {
    string: []const u8,

    pub fn garbageCollect(self: *String, allocator: std.mem.Allocator) void {
        if (self.string.len > 0) {
            allocator.free(self.string);
        }
        self.string = "";
    }

    pub fn markChildren(_: String, _: *ObjectManager) void {}
};

pub const List = struct {
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
};

test "val is small" {
    try std.testing.expectEqual(2 * @sizeOf(u64), @sizeOf(Val));
}
