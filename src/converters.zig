const std = @import("std");

const Error = @import("error.zig").Error;
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

/// Create a struct where each field contains a `Symbol.Interned`
/// corresponding to the name of that field.
///
/// ```zig
/// const symbols = try symbolTable(&vm, struct{ good: Symbol.Interned, bad: Symbol.Interned });
/// ```
pub fn symbolTable(self: *Vm, T: type) !T {
    const type_info = @typeInfo(T);
    const struct_info = switch (type_info) {
        .Struct => |s| s,
        else => @compileError("initSymbolTable type T must be struct but found type " ++ @typeName(T)),
    };
    var ret: T = undefined;
    inline for (struct_info.fields) |field| {
        if (field.type != Symbol.Interned) {
            @compileError(
                "initSymbolTable requires all members to be of type Symbol.Interned, but struct " ++
                    @typeName(T) ++ " has field " ++ field.name ++ " of type " ++
                    @typeName(field.type) ++ ".",
            );
        }
        const symbol = try Symbol.fromStr(field.name);
        @field(ret, field.name) = try symbol.intern(self);
    }
    return ret;
}

/// Parse `vals` into a struct of type `T`. The `nth` value in `vals`
/// is parsed into the `nth` field of `T`.
///
/// If `rest: []const Val` is present, any unparsed args will be
/// placed in rest.
///
/// WARNING: When `rest` is present, the remaining values are put into
/// the final field, reguardless if it is `rest` or not. TODO: Add
/// compile check to assert that `rest` is the final field.
pub fn parseAsArgs(
    T: type,
    vm: *Vm,
    vals: []const Val,
) !T {
    const has_rest = @hasField(T, "rest");
    const struct_info = switch (@typeInfo(T)) {
        .Struct => |s| s,
        else => @compileError("parseAsArgs type T must be struct but found type " ++ @typeName(T)),
    };
    const num_required_fields: comptime_int = if (has_rest) struct_info.fields.len - 1 else struct_info.fields.len;
    if (num_required_fields > vals.len) return Error.WrongArity;
    if (!has_rest and struct_info.fields.len < vals.len) return Error.WrongArity;

    var ret: T = undefined;
    inline for (struct_info.fields, 0..struct_info.fields.len) |field, idx| {
        if (has_rest and idx == struct_info.fields.len - 1)
            @field(ret, field.name) = vals[idx..]
        else
            @field(ret, field.name) = try vals[idx].toZig(field.type, vm);
    }
    return ret;
}

pub fn iter(T: type, vm: *const Vm, vals: []const Val) IterConverted(T) {
    return .{ .vm = vm, .vals = vals, .idx = 0 };
}

pub fn IterConverted(T: type) type {
    return struct {
        vm: *const Vm,
        vals: []const Val,
        idx: usize,

        pub fn next(self: *@This()) !?T {
            if (self.idx >= self.vals.len) return null;
            const v = self.vals[self.idx];
            self.idx += 1;
            return try v.toZig(T, self.vm);
        }
    };
}

test "can iterate over vals" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const vals = [_]Val{
        try Val.fromZig(&vm, 1),
        try Val.fromZig(&vm, 2.0),
        try Val.fromZig(&vm, 3),
    };

    var numbers_iter = iter(Val.Number, &vm, &vals);
    try std.testing.expectEqual(@as(Val.Number, .{ .int = 1 }), (try numbers_iter.next()).?);
    try std.testing.expectEqual(@as(Val.Number, .{ .float = 2.0 }), (try numbers_iter.next()).?);
    try std.testing.expectEqual(@as(Val.Number, .{ .int = 3 }), (try numbers_iter.next()).?);
    try std.testing.expectEqual(null, try numbers_iter.next());
}

test "can iterate over empty vals" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const vals: []const Val = &.{};
    var numbers_iter = iter(Val.Number, &vm, vals);
    try std.testing.expectEqual(null, try numbers_iter.next());
}

test "parseAsArgs into struct" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const Args = struct {
        a: i64,
        b: f64,
    };

    const vals = [_]Val{
        try Val.fromZig(&vm, 1),
        try Val.fromZig(&vm, 2.0),
    };

    const args = try parseAsArgs(Args, &vm, &vals);
    try std.testing.expectEqualDeep(Args{ .a = 1, .b = 2.0 }, args);
}

test "parseAsArgs with rest" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const Args = struct {
        a: i64,
        b: f64,
        rest: []const Val,
    };

    const vals = [_]Val{
        try Val.fromZig(&vm, 1),
        try Val.fromZig(&vm, 2.0),
        try Val.fromZig(&vm, 3),
        try Val.fromZig(&vm, @as([]const u8, "hello")),
    };

    const args = try parseAsArgs(Args, &vm, &vals);
    try std.testing.expectEqualDeep(
        Args{ .a = 1, .b = 2.0, .rest = vals[2..] },
        args,
    );
}

test "parseAsArgs with too few arguments" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const Args = struct {
        a: i64,
        b: f64,
    };

    const vals = [_]Val{try Val.fromZig(&vm, 1)};
    try std.testing.expectError(
        Error.WrongArity,
        parseAsArgs(Args, &vm, &vals),
    );
}

test "parseAsArgs with too few many arguments and no rest" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const Args = struct {
        a: i64,
        b: f64,
    };

    const vals = [_]Val{
        try Val.fromZig(&vm, 1),
        try Val.fromZig(&vm, 1),
        try Val.fromZig(&vm, 1),
        try Val.fromZig(&vm, 1),
    };
    try std.testing.expectError(
        Error.WrongArity,
        parseAsArgs(Args, &vm, &vals),
    );
}
