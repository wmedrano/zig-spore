const std = @import("std");

const ByteCodeFunction = @import("ByteCodeFunction.zig");
const Error = @import("error.zig").Error;
const NativeFunction = @import("NativeFunction.zig");
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const converters = @import("converters.zig");
const function = @import("builtins/function.zig");
const math = @import("builtins/math.zig");
const string = @import("builtins/string.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("%define", defineFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("do", doFn));
    try vm.global.registerFunction(vm, NativeFunction.init("list", listFn));
    try math.registerAll(vm);
    try string.registerAll(vm);
    try function.registerAll(vm);
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
    return Val.fromZig(vm, args);
}

test "do returns last expression" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(3, try vm.evalStr(i64, "(do 1 2 3)"));
}

test "do returns nil if no expressions" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr(Val, "(do)");
    try std.testing.expectEqual(Val.init(), actual);
}

test "list returns list of arguments" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr(Val, "(list 1 2 3)");
    const list = try actual.toZig([]const Val, &vm);
    try std.testing.expectEqual(@as(usize, 3), list.len);
    try std.testing.expectEqual(@as(i64, 1), try list[0].toZig(i64, &vm));
    try std.testing.expectEqual(@as(i64, 2), try list[1].toZig(i64, &vm));
    try std.testing.expectEqual(@as(i64, 3), try list[2].toZig(i64, &vm));
}
