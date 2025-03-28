const std = @import("std");

const AstBuilder = @import("AstBuilder.zig");
const Compiler = @import("Compiler.zig");
const Instruction = @import("instruction.zig").Instruction;
const Module = @import("Module.zig");
const Stack = @import("Stack.zig");
const Val = @import("Val.zig");
const builtins = @import("builtins.zig");
const function = @import("function.zig");

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
stack: Stack,

/// Options for operating the virtual machine.
pub const Options = struct {
    /// If logging is enabled.
    log: bool = false,

    /// The allocator to use. All objects on the `Vm` will use this
    /// allocator.
    allocator: std.mem.Allocator,
};

/// Create a new `Vm` with the given options.
pub fn init(options: Options) !Vm {
    const stack = try Stack.init(options.allocator);
    var vm = Vm{
        .options = options,
        .global = .{},
        .objects = .{},
        .stack = stack,
    };
    try builtins.registerAll(&vm);
    return vm;
}

/// Release all allocated memory.
pub fn deinit(self: *Vm) void {
    self.objects.deinit(self.allocator());
    self.stack.deinit(self.allocator());
    self.global.deinit(self.allocator());
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
        const instructions = try compiler.compile(ast.expr);
        defer self.allocator().free(instructions);
        self.stack.reset();
        const stack_frame = Stack.Frame{
            .instructions = instructions,
            .stack_start = 0,
            .next_instruction = 0,
        };
        try self.stack.frames.append(self.allocator(), stack_frame);
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

/// Run the garbage collector.
///
/// This reduces memory usage by cleaning up unused allocated `Val`s.
pub fn runGc(self: *Vm) !void {
    for (self.stack.items) |v| {
        self.objects.markReachable(v);
    }
    for (self.stack.frames.items) |stack_frame| {
        function.ByteCodeFunction.markInstructions(stack_frame.instructions, &self.objects);
    }
    var globalsIter = self.global.values.valueIterator();
    while (globalsIter.next()) |v| {
        self.objects.markReachable(v.*);
    }
    try self.objects.sweepUnreachable(self.allocator());
}

fn nextInstruction(self: Vm) ?Instruction {
    const frame = if (self.stack.currentFrame()) |f| f else return null;
    const is_ok = frame.next_instruction < frame.instructions.len;
    if (!is_ok) return .{ .ret = {} };
    const instruction = frame.instructions[frame.next_instruction];
    frame.next_instruction += 1;
    return instruction;
}
