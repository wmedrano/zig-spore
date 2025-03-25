const std = @import("std");
const InternedSymbol = @import("val.zig").InternedSymbol;
const Val = @import("val.zig").Val;
const Vm = @import("Vm.zig");

pub const InstructionTag = enum { push, eval, deref, ret };

pub const Instruction = union(InstructionTag) {
    push: Val,
    eval: u32,
    deref: InternedSymbol,
    ret,
};
