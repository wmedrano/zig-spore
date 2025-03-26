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
pub fn registerFunction(self: *Module, vm: *Vm, comptime function: type) !void {
    const wrapped_function = struct {
        const FUNCTION = Val.FunctionVal{
            .name = function.name,
            .function = function.fnImpl,
        };
    };
    try self.registerValueByName(
        vm,
        function.name,
        .{
            .repr = .{ .function = &wrapped_function.FUNCTION },
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
