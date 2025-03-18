pub const Vm = @import("vm.zig").Vm;
pub const VmOptions = @import("vm.zig").VmOptions;
pub const Val = @import("val.zig").Val;

const std = @import("std");

test "can make vm" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
}

test "can run gc" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    try vm.runGc();
    defer vm.deinit();
}

test "eval constant returns constant" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("12");
    try std.testing.expectEqual(Val{ .int = 12 }, actual);
}

test "eval can return symbol" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("'+");
    try std.testing.expectEqual(vm.newSymbol("+"), actual);
}

test "eval multiple constants returns last constant" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("12 true false 4.5");
    try std.testing.expectEqual(Val{ .float = 4.5 }, actual);
}

test "can define" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const define_actual = try vm.evalStr("(%define 'x 12)");
    try std.testing.expectEqual(Val{ .void = {} }, define_actual);
    const get_actual = try vm.evalStr("x");
    try std.testing.expectEqual(Val{ .int = 12 }, get_actual);
}
