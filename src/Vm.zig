const std = @import("std");
const testing = std.testing;

const AstBuilder = @import("AstBuilder.zig");
const Compiler = @import("Compiler.zig");
const Instruction = @import("instruction.zig").Instruction;
const Module = @import("Module.zig");
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const builtins = @import("builtins.zig");

const ObjectManager = @import("ObjectManager.zig");

const Vm = @This();

/// Contains settings for operating the virtual machine.
options: Options,

/// The global module. Contains globally available functions and
/// values.
global: Module,

/// Contains all allocated objects. You usually want to use `Vm.Val`
/// functions instead of using an `ObjectManager` directly.
objects: ObjectManager,

/// The virtual machine's stack.
///
/// Contains local variables for all function calls.
stack: []Val,

/// The length of the active stack. Anything outside of this is
/// invalid.
stack_len: usize,

/// Contains all current function calls.
stack_frames: std.ArrayListUnmanaged(StackFrame),

/// Options for operating the virtual machine.
pub const Options = struct {
    /// The size of the stack VM.
    ///
    /// Higher values use more memory, but may be needed to avoid
    /// stack overflow. Stack overflows occur when there is not enough
    /// stack capacity, which may stem from large function call stack or
    /// functions that need a lot of local state.
    comptime stack_size: usize = 4096,

    /// The allocator to use. All objects on the `Vm` will use this
    /// allocator.
    allocator: std.mem.Allocator,
};

/// Defines a function call.
pub const StackFrame = struct {
    /// The instructions for the function.
    instructions: []const Instruction,
    /// The location in the stack that mark's this functions base.
    stack_start: usize,
    /// The index of the next instruction to execute.
    next_instruction: usize,

    /// Returns `true` if all instructions have been executed.
    fn isDone(self: StackFrame) bool {
        const ok = self.next_instruction < self.instructions.len;
        return !ok;
    }
};

/// Create a new `Vm` with the given options.
pub fn init(options: Options) !Vm {
    const stack = try options.allocator.alloc(Val, options.stack_size);
    const stack_frames = try std.ArrayListUnmanaged(StackFrame).initCapacity(options.allocator, 256);
    var vm = Vm{
        .options = options,
        .global = .{},
        .objects = .{},
        .stack = stack,
        .stack_len = 0,
        .stack_frames = stack_frames,
    };
    try builtins.registerAll(&vm);
    return vm;
}

/// Get the allocator used for all objects in the virtual machine.
pub fn allocator(self: *Vm) std.mem.Allocator {
    return self.options.allocator;
}

/// Evaluate `source` as Spore code and return the result as type `T`.
///
/// If the return value does not matter, then using `Val` as `T` will
/// return the raw object without attempting any conversions.
///
/// If `source` contains multiple expressions, then only the last one
/// is returned.
///
/// Depending on what is inside `Val`, it may only be valid until the
/// next `Vm.runGc` call.
pub fn evalStr(self: *Vm, T: type, source: []const u8) !T {
    var ast_builder = AstBuilder.init(self, source);
    var compiler = try Compiler.init(self);
    defer compiler.deinit();
    var ret = Val.init();
    while (try ast_builder.next()) |ast| {
        try compiler.compile(ast.expr);
        self.resetStacks();
        const stack_frame = StackFrame{
            .instructions = compiler.currentExpr(),
            .stack_start = 0,
            .next_instruction = 0,
        };
        try self.stack_frames.append(self.allocator(), stack_frame);
        ret = try self.run();
    }
    return ret.toZig(T, self);
}

fn run(self: *Vm) !Val {
    var return_value = Val.init();
    while (self.nextInstruction()) |instruction| {
        if (try instruction.execute(self)) |v| {
            return_value = v;
        }
    }
    return return_value;
}

/// Release all allocated memory.
pub fn deinit(self: *Vm) void {
    self.objects.deinit(self.allocator());
    self.allocator().free(self.stack);
    self.stack_frames.deinit(self.allocator());
    self.global.deinit(self.allocator());
}

/// Run the garbage collector.
///
/// This reduces memory usage by cleaning up unused allocated `Val`s.
pub fn runGc(self: *Vm) !void {
    for (self.stack[0..self.stack_len]) |v| {
        self.objects.markReachable(v);
    }
    for (self.stack_frames.items) |stack_frame| {
        const bytecode_function = Val.ByteCodeFunction{
            .name = "", // Unused
            .instructions = stack_frame.instructions,
        };
        bytecode_function.markChildren(&self.objects);
    }
    var globalsIter = self.global.values.valueIterator();
    while (globalsIter.next()) |v| {
        self.objects.markReachable(v.*);
    }
    try self.objects.sweepUnreachable(self.allocator());
}

/// Get the values in the current function call's stack.
///
/// On a fresh function call, this is equivalent to getting the
/// function's arguments. Performing operations like evaluating more
/// code may mutate the local stack.
pub fn localStack(self: *Vm) []Val {
    const stack_start = if (self.stack_frames.getLastOrNull()) |sf| sf.stack_start else return &[0]Val{};
    return self.stack[stack_start..self.stack_len];
}

/// Push a new value to the virtual machine's stack.
pub fn pushStackVal(self: *Vm, val: Val) !void {
    if (self.stack_len < self.stack.len) {
        self.stack[self.stack_len] = val;
        self.stack_len += 1;
    } else {
        return Val.FunctionError.StackOverflow;
    }
}

fn resetStacks(self: *Vm) void {
    self.stack_len = 0;
    self.stack_frames.clearRetainingCapacity();
}

/// Push a new stack frame to the virtual machine.
pub fn pushStackFrame(self: *Vm, stack_frame: StackFrame) !void {
    try self.stack_frames.append(
        self.allocator(),
        stack_frame,
    );
}

/// Pop the current stack frame and get the value at the top of the local stack.
///
/// The value at the top of the stack is usually the return value. If
/// the stack is empty, then a void value is returned.
pub fn popStackFrame(self: *Vm) !Val {
    const stack_frame = if (self.stack_frames.popOrNull()) |x| x else return error.StackFrameUnderflow;
    const return_value = if (stack_frame.stack_start <= self.stack_len) self.stack[self.stack_len - 1] else Val.init();
    self.stack_len = stack_frame.stack_start;
    return return_value;
}

fn nextInstruction(self: Vm) ?Instruction {
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
