const std = @import("std");
const Val = @import("val.zig").Val;
const Instruction = @import("instruction.zig").Instruction;
const ObjectManager = @import("object_manager.zig").ObjectManager;

pub const Env = struct {
    objects: ObjectManager,
    stack: []Val,
    stack_len: usize,
    stack_frames: std.ArrayListUnmanaged(StackFrame),

    pub fn init(allocator: std.mem.Allocator, stack_size: usize) !Env {
        return Env{
            .objects = .{},
            .stack = try allocator.alloc(Val, stack_size),
            .stack_len = 0,
            .stack_frames = try std.ArrayListUnmanaged(StackFrame).initCapacity(allocator, 256),
        };
    }

    pub fn deinit(self: *Env, allocator: std.mem.Allocator) void {
        self.objects.deinit(allocator);
        allocator.free(self.stack);
        self.stack_frames.deinit(allocator);
    }

    pub fn pushVal(self: *Env, val: Val) !void {
        if (self.stack_len < self.stack.len) {
            self.stack[self.stack_len] = val;
            self.stack_len += 1;
        } else {
            return error.StackOverflow;
        }
    }

    pub fn topVal(self: *const Env) ?Val {
        if (self.stack_len == 0) {
            return null;
        }
        return self.stack[self.stack_len - 1];
    }

    pub fn resetStacks(self: *Env) void {
        self.stack_len = 0;
        self.stack_frames.clearRetainingCapacity();
    }

    pub fn popStackFrame(self: *Env) !Val {
        const stack_frame = if (self.stack_frames.popOrNull()) |x| x else return error.StackFrameUnderflow;
        const return_value = if (stack_frame.stack_start < self.stack_len) self.stack[self.stack_len - 1] else Val{ .void = {} };
        self.stack_len = stack_frame.stack_start;
        return return_value;
    }

    pub fn nextInstruction(self: *Env) ?Instruction {
        if (self.stack_frames.items.len == 0) {
            return null;
        }
        const stack_frame = &self.stack_frames.items[self.stack_frames.items.len - 1];
        if (stack_frame.isDone()) {
            return Instruction{ .ret = {} };
        }
        const instruction = stack_frame.instructions[stack_frame.next_instruction];
        stack_frame.next_instruction += 1;
        return instruction;
    }
};

pub const StackFrame = struct {
    instructions: []const Instruction,
    stack_start: usize = 0,
    next_instruction: usize = 0,

    fn isDone(self: *const StackFrame) bool {
        const ok = self.next_instruction < self.instructions.len;
        return !ok;
    }
};
