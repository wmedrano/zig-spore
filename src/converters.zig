const std = @import("std");

const Error = @import("root.zig").Error;
const Symbol = Val.Symbol;
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

/// Create a struct where each field contains a `Symbol.Interned`
/// corresponding to the name of that field.
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

test symbolTable {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const MySymbols = struct {
        foo: Symbol.Interned,
        bar: Symbol.Interned,
    };
    const symbols = try symbolTable(&vm, MySymbols);
    try std.testing.expectEqualStrings("foo", symbols.foo.toSymbol(&vm).?.name());
    try std.testing.expectEqualStrings("bar", symbols.bar.toSymbol(&vm).?.name());

    try std.testing.expectFmt("foo", "{any}", .{symbols.foo.toVal().formatted(&vm)});
    try std.testing.expectFmt("bar", "{any}", .{symbols.bar.toVal().formatted(&vm)});
}

/// Parse `vals` into a struct of type `T`. The `nth` value in `vals`
/// is parsed into the `nth` field of `T`.
///
/// If `T` has a field named `rest` of type `[]const Val`, any unparsed
/// `Val`s will be collected into a slice and assigned to the `rest` field.
///
/// Returns `Error.WrongArity` if there are not enough `Val`s to fill
/// the required fields of `T`, or if there are too many `Val`s and
/// `T` does not have a `rest` field.
///
/// # WARNING
/// When `rest` is present, the remaining values are put into the
/// final field, regardless if it is `rest` or not. TODO: Add compile
/// check to assert that `rest` is the final field.
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
            @field(ret, field.name) = try vals[idx].to(field.type, vm);
    }
    return ret;
}

test parseAsArgs {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const Args = struct {
        // The first argument.
        a: i64,
        // The second argument.
        b: f64,
        // Any other arguments. `rest` must be the last field and it
        // must be of type `[]const Val`.
        rest: []const Val,
    };

    const unparsed_args = [_]Val{
        try Val.from(&vm, 1),
        try Val.from(&vm, 2.0),
        try Val.from(&vm, 3),
        try Val.from(&vm, @as([]const u8, "hello")),
    };

    const args = try parseAsArgs(Args, &vm, &unparsed_args);
    try std.testing.expectEqualDeep(
        Args{ .a = 1, .b = 2.0, .rest = unparsed_args[2..] },
        args,
    );
}

test "parseAsArgs into struct" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const Args = struct {
        name: []const u8,
        age: i64,
    };
    const vals = [_]Val{
        try Val.from(&vm, @as([]const u8, "ziggling")),
        try Val.from(&vm, 12),
    };
    const args = try parseAsArgs(Args, &vm, &vals);
    try std.testing.expectEqualStrings(@as([]const u8, "ziggling"), args.name);
    try std.testing.expectEqual(12, args.age);
}

test "parseAsArgs with too few arguments" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const Args = struct {
        a: i64,
        b: f64,
    };

    const vals = [_]Val{try Val.from(&vm, 1)};
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
        try Val.from(&vm, 1),
        try Val.from(&vm, 1),
        try Val.from(&vm, 1),
        try Val.from(&vm, 1),
    };
    try std.testing.expectError(
        Error.WrongArity,
        parseAsArgs(Args, &vm, &vals),
    );
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
            return try v.to(T, self.vm);
        }
    };
}

test iter {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const vals = [_]Val{
        try Val.from(&vm, 1),
        try Val.from(&vm, 2.0),
        try Val.from(&vm, 3),
    };

    var numbers_iter = iter(Val.Number, &vm, &vals);
    try std.testing.expectEqual(Val.Number{ .int = 1 }, (try numbers_iter.next()).?);
    try std.testing.expectEqual(Val.Number{ .float = 2.0 }, (try numbers_iter.next()).?);
    try std.testing.expectEqual(Val.Number{ .int = 3 }, (try numbers_iter.next()).?);
    try std.testing.expectEqual(null, try numbers_iter.next());
}

test "can iterate over empty vals" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    const vals: []const Val = &.{};
    var numbers_iter = iter(Val.Number, &vm, vals);
    try std.testing.expectEqual(null, try numbers_iter.next());
}
