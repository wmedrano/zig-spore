const std = @import("std");
const testing = std.testing;
const Val = @import("val.zig").Val;
const Env = @import("env.zig").Env;
const Compiler = @import("compiler.zig").Compiler;

pub const VmOptions = struct {
    comptime stack_size: usize = 4096,
    allocator: std.mem.Allocator,
};

pub const Vm = struct {
    options: VmOptions,
    env: Env,

    pub fn init(options: VmOptions) !Vm {
        return Vm{
            .options = options,
            .env = try Env.init(options.allocator, options.stack_size),
        };
    }

    pub fn evalStr(_: *Vm, str: []const u8) !Val {
        var compiler = Compiler.init(str);
        var ret = Val{ .void = {} };
        while (try compiler.next()) |v| {
            ret = v;
        }
        return ret;
    }

    pub fn deinit(vm: *Vm) void {
        vm.options.allocator.free(vm.env.stack);
    }
};

test "can make vm" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
}

test "eval constant returns constant" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("12");
    try std.testing.expectEqual(Val{ .int = 12 }, actual);
}

test "eval multiple constants returns last constant" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("12 true false 4.5");
    try std.testing.expectEqual(Val{ .float = 4.5 }, actual);
}
