const std = @import("std");

const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

const Module = @This();

values: std.AutoHashMapUnmanaged(Val.InternedSymbol, Val) = .{},

pub fn deinit(self: *Module, allocator: std.mem.Allocator) void {
    self.values.deinit(allocator);
}

/// Register global function `function`.
///
/// - It is registered under the name `function.name`.
/// - The value pointed to by `function` must outlive the interpretter.
///
/// ```zig
/// fn add2Impl(vm: *Vm) Vm.Val.FunctionError!Vm.Val {
///     const args = vm.localStack();
///     if (args.len != 1) return Vm.Val.FunctionError.WrongArity;
///     const arg = args[0].asInt();
///     if (arg == null) return Vm.Val.FunctionError.WrongType;
///     return Vm.Val.fromInt(2 + arg.?);
/// }
///
/// var vm = try Vm.init(.{.allocator = std.testing.allocator});
/// defer vm.deinit();
/// try vm.global.registerFunction(&vm, &ADD_2_FN);
/// try std.testing.expectEqual(
///     Vm.Val.fromInt(10),
///     try vm.evalStr("(add-2 8)"),
/// );
/// ```
pub fn registerFunction(self: *Module, vm: *Vm, function: *const Val.FunctionVal) !void {
    try self.registerValueByName(
        vm,
        function.name,
        .{
            .repr = .{ .function = function },
        },
    );
}

pub fn registerValueByName(self: *Module, vm: *Vm, name: []const u8, value: Val) !void {
    const symbol = try vm.objects.symbols.strToSymbol(
        vm.allocator(),
        Symbol{ .quotes = 0, .name = name },
    );
    try self.registerValue(vm, symbol, value);
}

pub fn registerValue(self: *Module, vm: *Vm, symbol: Val.InternedSymbol, value: Val) !void {
    try self.values.put(vm.allocator(), symbol, value);
}

pub fn getValue(self: Module, symbol: Val.InternedSymbol) ?Val {
    return self.values.get(symbol);
}
