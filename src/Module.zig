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
/// - `name` - The name to register the function under. Must be unique
///        to the module or an error is returned.
/// - `func` - A function that takes `vm` and returns `Val.FunctionError!Val`.
///
/// ```zig
/// fn addTwo(vm: *Vm) Val.FunctionError!Val {
///     const args = vm.stack.local();
///     if (args.len != 1) return Val.FunctionError.WrongArity;
///     const arg = try args[0].toZig(i64, vm);
///     return Val.fromZig(vm, 2 + arg);
/// }
///
/// test "can eval custom fuction" {
///     var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
///     try vm.global.registerFunction(&vm, "add-2", addTwo);
///     defer vm.deinit();
///     try std.testing.expectEqual(
///         10,
///         try vm.evalStr(i64, "(add-2 8)"),
///     );
/// }
/// ```
pub fn registerFunction(self: *Module, vm: *Vm, comptime name: []const u8, comptime func: anytype) !void {
    const resolved_func = function.FunctionVal.init(name, func);
    const val = Val{
        .repr = .{ .function = resolved_func },
    };
    try self.registerValueByName(vm, name, val);
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
    try self.values.put(vm.allocator(), symbol, value);
}

/// Get a value from the module or `null` if it is not defined.
pub fn getValue(self: Module, symbol: Symbol.Interned) ?Val {
    return self.values.get(symbol);
}
