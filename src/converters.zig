const Vm = @import("Vm.zig");
const Symbol = @import("Symbol.zig");

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
