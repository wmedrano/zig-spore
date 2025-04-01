const std = @import("std");

const Error = @import("root.zig").Error;
const Instruction = @import("instruction.zig").Instruction;
const List = @import("List.zig");
const ObjectManager = @import("ObjectManager.zig");
const String = @import("String.zig");
const StringInterner = @import("StringInterner.zig");
const ToZigError = @import("error.zig").ToZigError;
const Vm = @import("Vm.zig");

pub const ByteCodeFunction = @import("ByteCodeFunction.zig");
pub const FormattedVal = @import("FormattedVal.zig");
pub const NativeFunction = @import("NativeFunction.zig");
pub const Number = @import("number.zig").Number;
pub const Symbol = @import("Symbol.zig");

const Val = @This();

/// The data inside the value. Prefer to use `fromZig` to construct a
/// new `Val` or `toZig` to extract from a `Val` when possible.
_repr: ValRepr,

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
    function: *const NativeFunction,
    bytecode_function: ObjectManager.Id(ByteCodeFunction),
};

/// Initialize a new `Val` to the default `void` value.
pub fn init() Val {
    return .{ ._repr = .{ .void = {} } };
}

test init {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const val = Val.init();
    try vm.global.registerValueByName(&vm, "void-val", val);
    try std.testing.expect(val.is(void));
    try std.testing.expectEqualDeep(
        {},
        try vm.evalStr(void, "void-val"),
    );
}

/// Convert from a Zig value to a Spore `Val`.
///
/// Supported Types:
/// - `Val` - Returns `val` as is.
/// - `void` - Converts to a `Val.void`.
/// - `bool` - Converts to a `Val.bool`.
/// - `i64` or `comptime_int` - Converts to a `Val.int`.
/// - `f64` or `comptime_float` - Converts to a `Val.float`.
/// - `Val.Number` - Converts to a value that holds an int or float.
/// - `[]const u8` or `[]u8` - Creates a new `Val.string` by copying the slice
///      contents. Note, string literals may require using `@as`:
///      `@as([]const u8, "my-string-literal")`
/// - `Symbol` - Converts to a `Val.symbol`.
/// - `Symbol.Interned` - Converts to a `Val.symbol`.
/// - `[]const Val` or `[]Val` - Converts to a `Val.list`.
/// - `?T` where T is supported - Converts to `T` or `void` if `T` is null.
pub fn fromZig(vm: *Vm, val: anytype) !Val {
    const T = @TypeOf(val);
    const type_info = @typeInfo(T);
    switch (type_info) {
        .Optional => {
            if (val) |v| {
                return fromZig(vm, v);
            }
            return init();
        },
        else => {},
    }
    switch (T) {
        Val => return val,
        void => return init(),
        bool => return .{ ._repr = .{ .bool = val } },
        i64, comptime_int => return .{ ._repr = .{ .int = @as(i64, val) } },
        f64, comptime_float => return .{ ._repr = .{ .float = @as(f64, val) } },
        Number => switch (val) {
            .int => |x| return .{ ._repr = .{ .int = x } },
            .float => |x| return .{ ._repr = .{ .float = x } },
        },
        []const u8, []u8 => {
            const owned_string = try vm.allocator().dupe(u8, val);
            errdefer vm.allocator().free(owned_string);
            const id = try vm.objects.put(
                String,
                vm.allocator(),
                .{ .string = owned_string },
            );
            return .{ ._repr = .{ .string = id } };
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
        else => @compileError(
            "fromZig not supported for type " ++ @typeName(T) ++ ".",
        ),
    }
}

test fromZig {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();

    try vm.global.registerValueByName(
        &vm,
        "magic-number",
        try Val.fromZig(&vm, 42),
    );
    try std.testing.expectEqualDeep(
        Val.Number{ .int = 43 },
        try vm.evalStr(Val.Number, "(+ magic-number 1)"),
    );

    // `*const Vm` type.
    try vm.global.registerValueByName(
        &vm,
        "magic-string",
        try Val.fromZig(&vm, @as([]const u8, "my-string")),
    );
    try std.testing.expectEqualStrings(
        "my-string",
        try vm.evalStr([]const u8, "magic-string"),
    );

    // Optional type.
    const optional_val: ?i64 = null;
    try vm.global.registerValueByName(
        &vm,
        "optional-val",
        try Val.fromZig(&vm, optional_val),
    );
    try std.testing.expectEqualDeep({}, try vm.evalStr(void, "optional-val"));
    try std.testing.expectEqualDeep(null, try vm.evalStr(?i64, "optional-val"));
}

/// Convert from a Spore `Val` to a Zig value of type `T`.
///
/// # Supported Types
///
/// The following types may pass either `void` or a `*const Vm` as the
/// `vm`:
/// - `void`, `bool`, `i64`, `f64`, `Val.Number`
/// - `Symbol.Interned`, `Symbol.InternedKey`
/// - `*const NativeFunction`
///
/// The following types require passing `*const Vm` as the `vm`.
/// - `[]const u8` (returns a slice pointing to the Val's internal string)
/// - `Symbol`, `Symbol.Key`
/// - `[]const Val` (returns a slice pointing to the Val's internal list)
/// - `ByteCodeFunction` - The Zig datastructure for a Spore VM function.
///
/// The following types depend:
/// - `?T` where T is a supported type. `*const Vm` is required for
///   `?T` if `T` requires a `*const Vm`.
///
/// # Lifetime Warning
/// For slice types (`[]const u8`, `[]const Val`), the returned slice's
/// lifetime is tied to the underlying object in the Vm's ObjectManager.
/// The caller must ensure the Vm and its objects outlive the use of the slice.
pub fn toZig(self: Val, comptime T: type, vm: anytype) ToZigError!T {
    const VmType = @TypeOf(vm);
    if (VmType != *const Vm and VmType != *Vm and VmType != void) {
        @compileError(
            "`vm` argument to `toZig` must be a `*const Vm` or `void` but got `" ++
                @typeName(VmType) ++ "`.",
        );
    }
    if (T == Val) return self;
    switch (self._repr) {
        .void => {
            if (T == void) return;
            if (@as(std.builtin.TypeId, @typeInfo(T)) == std.builtin.TypeId.Optional) {
                return null;
            }
            return ToZigError.WrongType;
        },
        .bool => |v| return boolToZig(T, v),
        .int => |v| return intToZig(T, v),
        .float => |v| return floatToZig(T, v),
        .string => |id| return stringToZig(T, vm, id),
        .symbol => |interned_symbol| return symbolToZig(T, vm, interned_symbol),
        .key => |interned_key| return keyToZig(T, vm, interned_key),
        .list => |id| return listToZig(T, vm, id),
        .function => |func| switch (T) {
            *const NativeFunction, ?*const NativeFunction => return func,
            else => return ToZigError.WrongType,
        },
        .bytecode_function => |bytecode_id| switch (T) {
            ByteCodeFunction, ?ByteCodeFunction => {
                const maybe_bytecode = vm.objects.get(ByteCodeFunction, bytecode_id);
                if (maybe_bytecode) |b| return b.* else return ToZigError.ObjectNotFound;
            },
            else => return ToZigError.WrongType,
        },
    }
}

test toZig {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const number = try vm.evalStr(Val, "100");
    try std.testing.expectEqualDeep(100, try number.toZig(i64, &vm));
    try std.testing.expectEqualDeep(Val.Number{ .int = 100 }, try number.toZig(Val.Number, &vm));

    const str = try vm.evalStr(Val, @as([]const u8, "\"string\""));
    try std.testing.expectEqualStrings("string", try str.toZig([]const u8, &vm));
}

/// Returns `true` if `self` can be converted into `T`.
///
/// The actual conversion can be done with `toZig`.
pub fn is(self: Val, comptime T: type) bool {
    if (T == Val) return true;
    switch (self._repr) {
        .void => {
            if (T == void) return true;
            if (@as(std.builtin.TypeId, @typeInfo(T)) == std.builtin.TypeId.Optional) {
                return true;
            }
            return false;
        },
        .bool => return T == bool or T == ?bool,
        .int => return T == i64 or T == Number or T == ?i64 or T == ?Number,
        .float => return T == f64 or T == Number or T == ?f64 or T == ?Number,
        .string => return T == []const u8 or T == ?[]const u8,
        .symbol => return T == Symbol.Interned or T == Symbol or T == ?Symbol.Interned or T == ?Symbol,
        .key => return T == Symbol.Key or T == Symbol.InternedKey or T == ?Symbol.Key or T == ?Symbol.InternedKey,
        .list => return T == []const Val or T == ?[]const u8,
        .function => return T == *const NativeFunction,
        .bytecode_function => return T == ByteCodeFunction or T == ?ByteCodeFunction,
    }
}

test is {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();

    try std.testing.expect(Val.init().is(void));

    const string_val = try vm.evalStr(Val, "\"my-string\"");
    try std.testing.expect(string_val.is([]const u8));

    const int_val = try vm.evalStr(Val, "4");
    try std.testing.expect(int_val.is(i64));
    try std.testing.expect(int_val.is(Val.Number));

    const float_val = try vm.evalStr(Val, "4.0");
    try std.testing.expect(float_val.is(f64));
    try std.testing.expect(float_val.is(Val.Number));

    const list_val = try vm.evalStr(Val, "(list 1 2 3)");
    try std.testing.expect(list_val.is([]const Val));
}

fn boolToZig(comptime T: type, x: bool) ToZigError!T {
    switch (T) {
        bool, ?bool => return x,
        else => return ToZigError.WrongType,
    }
}

fn intToZig(comptime T: type, x: i64) ToZigError!T {
    switch (T) {
        i64, ?i64 => return x,
        Number, ?Number => return Number{ .int = x },
        else => return ToZigError.WrongType,
    }
}

fn floatToZig(comptime T: type, x: f64) ToZigError!T {
    switch (T) {
        f64, ?f64 => return x,
        Number, ?Number => return Number{ .float = x },
        else => return ToZigError.WrongType,
    }
}

fn stringToZig(comptime T: type, vm: anytype, id: ObjectManager.Id(String)) ToZigError!T {
    switch (T) {
        []const u8, ?[]const u8 => {
            const maybe_string = vm.objects.get(String, id);
            if (maybe_string) |s| return s.string else return ToZigError.ObjectNotFound;
        },
        else => return ToZigError.WrongType,
    }
}

fn symbolToZig(comptime T: type, vm: anytype, interned_symbol: Symbol.Interned) ToZigError!T {
    switch (T) {
        Symbol.Interned, ?Symbol.Interned => return interned_symbol,
        Symbol, ?Symbol => {
            const maybe_str = vm.objects.string_interner.getString(interned_symbol.id);
            if (maybe_str) |str| {
                return .{ ._quotes = interned_symbol.quotes, ._name = str };
            }
            return ToZigError.ObjectNotFound;
        },
        else => return ToZigError.WrongType,
    }
}

fn keyToZig(comptime T: type, vm: anytype, interned_key: Symbol.InternedKey) ToZigError!T {
    switch (T) {
        Symbol.InternedKey, ?Symbol.InternedKey => return interned_key,
        Symbol.Key, ?Symbol.Key => {
            const maybe_key_name = vm.objects.string_interner.getString(interned_key.id);
            if (maybe_key_name) |name| {
                return Symbol.Key{ .name = name };
            }
            return ToZigError.ObjectNotFound;
        },
        else => return ToZigError.WrongType,
    }
}

fn listToZig(comptime T: type, vm: anytype, id: ObjectManager.Id(List)) ToZigError!T {
    const VmType = @TypeOf(vm);
    switch (T) {
        []const Val, ?[]const Val => {
            const maybe_list = vm.objects.get(List, id);
            if (maybe_list) |l| return l.list else return ToZigError.ObjectNotFound;
        },
        else => {
            if (VmType == *Vm or VmType == *const Vm) {
                if (vm.options.log) std.log.err(
                    "Expected type {s} but got list",
                    .{@typeName(T)},
                );
            }
            return ToZigError.WrongType;
        },
    }
}

/// Returns `true` if `self` is truthy.
///
/// All values are truthy except for `void` and `false`.
pub fn isTruthy(self: Val) bool {
    return switch (self._repr) {
        .void => false,
        .bool => |b| b,
        else => true,
    };
}

/// Create a new from `owned_list`.
///
/// `owned_list` must be allocated on `vm.allocator()`.
pub fn fromOwnedList(vm: *Vm, owned_list: []Val) !Val {
    const id = try vm.objects.put(List, vm.allocator(), .{ .list = owned_list });
    return .{ ._repr = .{ .list = id } };
}

/// Get a struct that can format `Val`.
pub fn formatted(self: Val, vm: *const Vm) FormattedVal {
    return FormattedVal{ .val = self, .vm = vm };
}

test formatted {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const val = try vm.evalStr(Val, "(list 1 2 3 4)");
    try std.testing.expectFmt("(1 2 3 4)", "{any}", .{val.formatted(&vm)});
}

/// Execute `self` if `self` is a proper function.
pub fn executeWith(self: Val, vm: *Vm, args: []const Val) Error!Val {
    switch (self._repr) {
        .function => |f| {
            return f.executeWith(vm, args);
        },
        .bytecode_function => |id| {
            const maybe_bytecode = vm.objects.get(ByteCodeFunction, id);
            const bytecode = if (maybe_bytecode) |bc| bc else return Error.ObjectNotFound;
            // Prevent garbage collection of `self`.
            try vm.stack.push(self);
            defer _ = vm.stack.pop();
            return bytecode.executeWith(vm, args);
        },
        else => return Error.ExpectedFunction,
    }
}

test executeWith {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const func = try vm.evalStr(Val, "(function (a b) (+ a b))");
    const args = [_]Val{ try Val.fromZig(&vm, 1), try Val.fromZig(&vm, 2) };
    const res = try func.executeWith(&vm, &args);
    try std.testing.expectEqual(3, res.toZig(i64, {}));
}

test "null to Zig returns void" {
    var vm = try Vm.init(.{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const null_value: ?i64 = null;
    const not_null_value: ?i64 = 10;

    try std.testing.expectEqual(
        Val.init(),
        try Val.fromZig(&vm, null_value),
    );
    try std.testing.expectEqual(
        Val.fromZig(&vm, 10),
        try Val.fromZig(&vm, not_null_value),
    );
}

test "val is small" {
    try std.testing.expectEqual(2 * @sizeOf(u64), @sizeOf(Val));
}
