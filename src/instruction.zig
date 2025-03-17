const std = @import("std");
const Val = @import("val.zig").Val;
const Vm = @import("root.zig").Vm;

pub const InstructionTag = enum { push, eval, ret };

pub const Instruction = union(InstructionTag) {
    push: Val,
    eval: u32,
    ret,
};
