const std = @import("std");

const Instruction = @import("instruction.zig").Instruction;
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const config = @import("config.zig");
const function = @import("function.zig");

const Stack = @This();

/// All items contained on the stack across all frames.
items: []Val,

/// All available frames.
///
/// A frame stores information about each function call.
frames: std.ArrayListUnmanaged(Frame),

/// Defines a function call.
pub const Frame = struct {
    /// The instructions for the function.
    instructions: []const Instruction,
    /// The location in the stack that mark's this functions base.
    stack_start: usize,
    /// The index of the next instruction to execute.
    next_instruction: usize,
};

/// Initialize a new `Stack`.
pub fn init(allocator: std.mem.Allocator) !Stack {
    var items = try allocator.alloc(Val, config.max_stack_len);
    items.len = 0;
    const frames = try std.ArrayListUnmanaged(Stack.Frame).initCapacity(allocator, 256);
    return .{
        .items = items,
        .frames = frames,
    };
}

pub fn deinit(self: *Stack, allocator: std.mem.Allocator) void {
    allocator.free(self.items.ptr[0..config.max_stack_len]);
    self.frames.deinit(allocator);
}

pub fn reset(self: *Stack) void {
    self.items.len = 0;
    self.frames.clearRetainingCapacity();
}

/// Pop the top value of the stack.
pub fn pop(self: *Stack) Val {
    if (self.items.len == 0) {
        return Val.init();
    }
    const ret = self.items[self.items.len - 1];
    self.items.len -= 1;
    return ret;
}

pub fn push(self: *Stack, val: Val) !void {
    try self.pushMany(&.{val});
}

pub fn pushMany(self: *Stack, vals: []const Val) !void {
    if (self.items.len + vals.len > config.max_stack_len) return function.Error.StackOverflow;
    const start = self.items.len;
    const end = start + vals.len;
    self.items.len = end;
    for (start..end, vals) |idx, val| {
        self.items[idx] = val;
    }
}

pub fn currentFrame(self: Stack) ?*Frame {
    if (self.frames.items.len == 0) {
        return null;
    }
    return &self.frames.items[self.frames.items.len - 1];
}

/// Push a new stack frame to the virtual machine.
pub fn pushFrame(self: *Stack, frame: Frame) !void {
    if (self.frames.capacity == self.frames.items.len) return function.Error.StackOverflow;
    self.frames.appendAssumeCapacity(frame);
}

/// Pop the current stack frame and get the value at the top of the
/// local stack.
///
/// The value at the top of the stack is usually the return value. If
/// the stack is empty, then a void value is returned.
pub fn popFrame(self: *Stack) function.Error!Val {
    const frame = if (self.frames.popOrNull()) |x| x else return function.Error.StackFrameUnderflow;
    const return_value = if (frame.stack_start <= self.items.len and self.items.len > 0)
        self.items[self.items.len - 1]
    else
        Val.init();
    self.items.len = frame.stack_start;
    return return_value;
}

/// Get the values in the current function call's stack.
///
/// On a fresh function call, this is equivalent to getting the
/// function's arguments. Performing operations like evaluating more
/// code may mutate the local stack.
pub fn local(self: Stack) []Val {
    const stack_start = if (self.frames.getLastOrNull()) |sf| sf.stack_start else return &.{};
    return self.items[stack_start..self.items.len];
}
