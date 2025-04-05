const std = @import("std");
const root = @import("../root.zig");

const ByteCodeFunction = Val.ByteCodeFunction;
const Error = root.Error;
const NativeFunction = Val.NativeFunction;
const Symbol = Val.Symbol;
const Val = root.Val;
const Vm = root.Vm;
const converters = @import("../converters.zig");

/// Registers all built-in functions and values into the virtual
/// machine.
pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, NativeFunction.withArgParser(.{ .name = "%define" }, defineFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser(.{ .name = "do" }, doFn));
    try vm.global.registerFunction(vm, NativeFunction.init(.{ .name = "list" }, listFn));
    try @import("function.zig").registerAll(vm);
    try @import("math.zig").registerAll(vm);
    try @import("sexp.zig").registerAll(vm);
    try @import("string.zig").registerAll(vm);
    try @import("macros.zig").registerAll(vm);
}

test registerAll {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    // Check that some basic functions are registered.
    try std.testing.expect(vm.global.getValueByName(&vm, "+") != null);
    try std.testing.expect(vm.global.getValueByName(&vm, "str-len") != null);
    try std.testing.expect(vm.global.getValueByName(&vm, "list") != null);

    // Verify that a simple expression can be evaluated using the builtins.
    _ = try vm.evalStr("(def my-const 3)");
    const val = try vm.evalStr("(list (do 'ignore (+ 3 3)))");
    try std.testing.expectFmt("(6)", "{any}", .{val.formatted(&vm)});
}

fn defineFn(vm: *Vm, args: struct { symbol: Symbol.Interned, value: Val }) Error!Val {
    try vm.global.registerValue(
        vm,
        args.symbol,
        args.value,
    );
    return Val.init();
}

pub fn doFn(_: *Vm, args: struct { rest: []const Val }) Error!Val {
    if (args.rest.len == 0) return Val.init();
    return args.rest[args.rest.len - 1];
}

fn listFn(vm: *Vm) Error!Val {
    const args = vm.stack.local();
    return Val.from(vm, args);
}

test "do returns last expression" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(3, try vm.to(i64, try vm.evalStr("(do 1 2 3)")));
}

test "do returns nil if no expressions" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("(do)");
    try std.testing.expectEqual(Val.init(), actual);
}

test "list returns list of arguments" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("(list 1 2 3)");
    const list = try actual.to([]const Val, &vm);
    try std.testing.expectEqual(@as(usize, 3), list.len);
    try std.testing.expectEqual(@as(i64, 1), try list[0].to(i64, &vm));
    try std.testing.expectEqual(@as(i64, 2), try list[1].to(i64, &vm));
    try std.testing.expectEqual(@as(i64, 3), try list[2].to(i64, &vm));
}
