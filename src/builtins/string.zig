const std = @import("std");

const SexpBuilder = @import("../compiler/SexpBuilder.zig");
const Error = @import("../error.zig").Error;
const NativeFunction = Val.NativeFunction;
const Val = Vm.Val;
const Vm = @import("../Vm.zig");
const converters = @import("../converters.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, NativeFunction.withArgParser(.{ .name = "str-len" }, strLenFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser(.{ .name = "print" }, printFn));
}

pub fn strLenFn(vm: *Vm, args: struct { str: []const u8 }) Error!Val {
    const len: i64 = @intCast(args.str.len);
    return Val.from(vm, len);
}

test "str-len returns string length" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(4, try vm.to(i64, try vm.evalStr("(str-len \"1234\")")));
}

fn printFn(vm: *Vm, args: struct { val: Val }) Error!Val {
    if (args.val.is([]const u8)) {
        const str = try args.val.to([]const u8, vm);
        std.debug.print("{s}\n", .{str});
    } else {
        const formatted = args.val.formatted(vm);
        std.debug.print("{any}\n", .{formatted});
    }
    return Val.init();
}
