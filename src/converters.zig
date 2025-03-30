const std = @import("std");

const Symbol = @import("Symbol.zig");
const Val = @import("./Val.zig");
const Vm = @import("Vm.zig");
const function = @import("function.zig");

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
        const symbol = Symbol{ .quotes = 0, .name = field.name };
        @field(ret, field.name) = try symbol.intern(self);
    }
    return ret;
}

/// Parse `vals` into a struct of type `T`. The `nth` value in `vals`
/// is parsed into the `nth` field of `T`.
pub fn parseAsArgs(
    T: type,
    vm: *Vm,
    vals: []const Val,
) !T {
    const has_rest = @hasField(T, "rest");
    const type_info = @typeInfo(T);
    const struct_info = switch (type_info) {
        .Struct => |s| s,
        else => @compileError("parseAsArgs type T must be struct but found type " ++ @typeName(T)),
    };
    var ret: T = undefined;
    if (struct_info.fields.len > vals.len) return function.Error.WrongArity;
    if (!has_rest and struct_info.fields.len < vals.len) return function.Error.WrongArity;
    inline for (struct_info.fields, 0..struct_info.fields.len) |field, idx| {
        if (has_rest and idx == struct_info.fields.len - 1) {
            @field(ret, field.name) = vals[idx..];
            continue;
        }
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
