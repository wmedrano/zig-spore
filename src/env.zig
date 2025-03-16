const Val = @import("val.zig").Val;
const std = @import("std");

pub const Env = struct {
    stack: []Val,
    stack_len: usize,

    pub fn init(allocator: std.mem.Allocator, stack_size: usize) !Env {
        return Env{
            .stack = try allocator.alloc(Val, stack_size),
            .stack_len = 0,
        };
    }
};
