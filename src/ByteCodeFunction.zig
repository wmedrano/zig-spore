const std = @import("std");

const Error = @import("error.zig").Error;
const Instruction = @import("instruction.zig").Instruction;
const ObjectManager = @import("ObjectManager.zig");
const Stack = @import("Stack.zig");
const Vm = @import("Vm.zig");

const ByteCodeFunction = @This();

/// The name of the bytecode function.
name: []const u8,
/// The instructions in the bytecode function.
instructions: []const Instruction,
/// The number of arguments.
args: u32,

pub fn garbageCollect(self: *ByteCodeFunction, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    allocator.free(self.instructions);
}

pub fn markChildren(self: ByteCodeFunction, marker: ObjectManager.Marker) void {
    markInstructions(self.instructions, marker);
}

pub fn markInstructions(instructions: []const Instruction, marker: ObjectManager.Marker) void {
    for (instructions) |instruction| {
        switch (instruction) {
            .push => |v| marker.markReachable(v),
            .eval => {},
            .get_local => {},
            .deref => {},
            .jump_if => {},
            .jump => {},
            .ret => {},
        }
    }
}

/// Start the execution of `self` on `vm`.
///
/// Note that `Vm` must run in order for the function to fully
/// evaluate. `startExecute` only begins the execution.
pub fn startExecute(self: ByteCodeFunction, vm: *Vm, stack_start: usize) !void {
    const arg_count = vm.stack.items.len - stack_start;
    if (self.args != arg_count) return Error.WrongArity;
    try vm.stack.pushFrame(
        Stack.Frame{
            .instructions = self.instructions,
            .stack_start = stack_start,
            .next_instruction = 0,
        },
    );
}
