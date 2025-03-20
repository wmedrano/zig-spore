const std = @import("std");
const Symbol = @import("val.zig").Symbol;
const Val = @import("val.zig").Val;
const Vm = @import("vm.zig").Vm;

pub const InstructionTag = enum { push, eval, deref, ret };

pub const Instruction = union(InstructionTag) {
    push: Val,
    eval: u32,
    deref: Symbol,
    ret,
};
