const std = @import("std");

const StringInterner = @import("StringInterner.zig");
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const function = @import("function.zig");

const Module = @This();

/// The name of the module.
name: StringInterner.Id,

/// The values stored in the hashmap.
values: std.AutoHashMapUnmanaged(Symbol.Interned, Val) = .{},

pub fn deinit(self: *Module, allocator: std.mem.Allocator) void {
    self.values.deinit(allocator);
}

/// Register a Zig function into the module.
///
/// - `vm` - The virtual machine for the module.
/// - `func` - The `function.FunctionVal` to register.
///
/// ```zig
/// fn addTwo(vm: *Vm, args: struct{ number: i64 }) Val.FunctionError!Val {
///     return Val.fromZig(vm, 2 + args.number);
/// }
///
/// test "can eval custom fuction" {
///     var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
///     defer vm.deinit();
///     try vm.global.registerFunction(&vm, function.FunctionVal.withArgParser("add-2", addTwo));
///     try std.testing.expectEqual(
///         10,
///         try vm.evalStr(i64, "(add-2 8)"),
///     );
/// }
/// ```
pub fn registerFunction(self: *Module, vm: *Vm, func: *const function.FunctionVal) !void {
    if (func.name.len == 0 or func.name[0] == '\'') return function.Error.ExpectedIdentifier;
    const interned_name = try vm.objects.string_interner.intern(vm.allocator(), func.name);
    const val = Val{
        .repr = .{ .function = func },
    };
    try self.registerValue(
        vm,
        .{ .quotes = 0, .id = interned_name.id },
        val,
    );
}

/// Register a value into the module. `name` must not already be
/// defined or `error.ValueAlreadyDefined` is returned.
pub fn registerValueByName(self: *Module, vm: *Vm, name: []const u8, value: Val) !void {
    const symbol = try Symbol.fromStr(name);
    if (symbol.quotes != 0) return error.TooManyQuotes;
    const interned_symbol = try symbol.intern(vm);
    try self.registerValue(vm, interned_symbol, value);
}

/// Register a value into the module. `symbol` must not already be defined
/// or `error.ValueAlreadyDefined` is returned.
pub fn registerValue(self: *Module, vm: *Vm, symbol: Symbol.Interned, value: Val) !void {
    if (self.values.contains(symbol)) return function.Error.ValueAlreadyDefined;
    if (symbol.quotes > 0) return function.Error.TooManyQuotes;
    try self.values.put(vm.allocator(), symbol, value);
}

/// Get a value from the module or `null` if it is not defined.
pub fn getValue(self: Module, symbol: Symbol.Interned) ?Val {
    return self.values.get(symbol);
}
