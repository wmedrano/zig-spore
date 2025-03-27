const std = @import("std");

const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const function = @import("function.zig");

const Module = @This();

values: std.AutoHashMapUnmanaged(Symbol.Interned, Val) = .{},

pub fn deinit(self: *Module, allocator: std.mem.Allocator) void {
    self.values.deinit(allocator);
}

/// Register a global function.
///
/// See `function.FunctionVal.init` for the specification for `func`.
///
/// ```zig
/// const Add2Fn = struct {
///     pub const name = "add-2";
///     pub fn fnImpl(vm: *Vm) Val.FunctionError!Val {
///         const args = vm.localStack();
///         if (args.len != 1) return Val.FunctionError.WrongArity;
///         const arg = try args[0].toZig(i64, vm);
///         return Val.fromZig(i64, vm, 2 + arg);
///     }
/// };
///
/// test "can eval custom fuction" {
///     var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
///     try vm.global.registerFunction(&vm, Add2Fn);
///     defer vm.deinit();
///     try std.testing.expectEqual(
///         10,
///         try vm.evalStr(i64, "(add-2 8)"),
///     );
/// }
/// ```
pub fn registerFunction(self: *Module, vm: *Vm, comptime func: type) !void {
    try self.registerValueByName(
        vm,
        func.name,
        .{
            .repr = .{ .function = function.FunctionVal.init(func) },
        },
    );
}

pub fn registerValueByName(self: *Module, vm: *Vm, name: []const u8, value: Val) !void {
    const symbol = try Symbol.fromStr(name);
    if (symbol.quotes != 0) return error.TooManyQuotes;
    const interned_symbol = try symbol.intern(vm);
    try self.registerValue(vm, interned_symbol, value);
}

pub fn registerValue(self: *Module, vm: *Vm, symbol: Symbol.Interned, value: Val) !void {
    try self.values.put(vm.allocator(), symbol, value);
}

pub fn getValue(self: Module, symbol: Symbol.Interned) ?Val {
    return self.values.get(symbol);
}
