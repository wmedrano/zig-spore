const std = @import("std");
const testing = std.testing;
const Val = @import("val.zig").Val;
const Env = @import("env.zig").Env;

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

    pub fn deinit(vm: *Vm) void {
        vm.options.allocator.free(vm.env.stack);
    }
};

test "can make vm" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
}
