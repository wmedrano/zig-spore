const std = @import("std");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

pub const InstructionTag = enum { push, eval, deref, ret };

pub const Instruction = union(InstructionTag) {
    push: Val,
    eval: u32,
    deref: Val.InternedSymbol,
    ret,
};
