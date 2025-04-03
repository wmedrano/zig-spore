const std = @import("std");

const Error = @import("root.zig").Error;
const NativeFunction = Val.NativeFunction;
const StringInterner = @import("StringInterner.zig");
const Symbol = Val.Symbol;
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

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
/// - `func` - The `NativeFunction` to register.
pub fn registerFunction(self: *Module, vm: *Vm, func: *const NativeFunction) !void {
    if (func.name.len == 0 or func.name[0] == '\'') return Error.ExpectedIdentifier;
    const interned_name = try vm.objects.string_interner.intern(vm.allocator(), func.name);
    const val = Val{
        ._repr = .{ .function = func },
    };
    try self.registerValue(
        vm,
        .{ .quotes = 0, .id = interned_name.id },
        val,
    );
}

fn addTwo(vm: *Vm, args: struct { number: i64 }) Error!Val {
    return Val.from(vm, 2 + args.number);
}

test registerFunction {
    // fn addTwo(vm: *Vm, args: struct { number: i64 }) Error!Val {
    //     return Val.from(vm, 2 + args.number);
    // }
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.global.registerFunction(&vm, NativeFunction.withArgParser("add-2", addTwo));
    try std.testing.expectEqual(
        10,
        try vm.to(i64, try vm.evalStr("(add-2 8)")),
    );
}

/// Register a value into the module. `name` must not already be
/// defined or `error.ValueAlreadyDefined` is returned.
pub fn registerValueByName(self: *Module, vm: *Vm, name: []const u8, value: Val) !void {
    const symbol = try Symbol.fromStr(name);
    if (symbol.isQuoted()) return error.TooManyQuotes;
    const interned_symbol = try symbol.intern(vm);
    try self.registerValue(vm, interned_symbol, value);
}

/// Register a value into the module. `symbol` must not already be defined
/// or `error.ValueAlreadyDefined` is returned.
pub fn registerValue(self: *Module, vm: *Vm, symbol: Symbol.Interned, value: Val) !void {
    if (self.values.contains(symbol)) return Error.ValueAlreadyDefined;
    if (symbol.quotes > 0) return Error.TooManyQuotes;
    try self.values.put(vm.allocator(), symbol, value);
}

/// Get a value from the module or `null` if it is not defined.
pub fn getValue(self: Module, symbol: Symbol.Interned) ?Val {
    return self.values.get(symbol);
}

/// Get a value from the module or `null` if it is not defined.
pub fn getValueByName(self: Module, vm: *const Vm, name: []const u8) ?Val {
    const symbol = Symbol.fromStr(name) catch return null;
    if (symbol.isQuoted()) return null;
    const interned_id = if (vm.objects.string_interner.getId(symbol.name())) |id| id else return null;
    const interned_symbol: Symbol.Interned = .{
        .quotes = 0,
        .id = interned_id,
    };
    return self.getValue(interned_symbol);
}
