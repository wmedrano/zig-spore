//! The Spore virtual machine used to execute Spore code.
//!
//! `Vm.evalStr` can be used to evaluate code. To register values, see
//! methods like `Module.registerValue` and `Module.registerFunction`.
const std = @import("std");

const AstBuilder = @import("compiler/AstBuilder.zig");
const ByteCodeFunction = Val.ByteCodeFunction;
const Compiler = @import("compiler/Compiler.zig");
const Error = @import("root.zig").Error;
const Instruction = @import("instruction.zig").Instruction;
const ObjectManager = @import("ObjectManager.zig");
const Stack = @import("Stack.zig");
const Symbol = Val.Symbol;
const builtins = @import("builtins/builtins.zig");

pub const Module = @import("Module.zig");
pub const Val = @import("Val.zig");

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
    /// If logging should be enabled. This is useful for printing out
    /// more information on errors.
    log: bool = true,

    /// The allocator to use. All objects on the `Vm` will use this
    /// allocator.
    allocator: std.mem.Allocator,
};

/// Create a new `Vm` with the given options.
pub fn init(options: Options) !Vm {
    const stack = try Stack.init(options.allocator);
    var objects = ObjectManager{};
    const global_name = try objects.string_interner.internToId(options.allocator, "");
    var vm = Vm{
        .options = options,
        .global = .{ .name = global_name },
        .objects = objects,
        .stack = stack,
    };
    try builtins.registerAll(&vm);
    return vm;
}

test init {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.evalStr(void,
        \\ (defun fib (n)
        \\   (if (< n 2) (return n))
        \\   (+ (fib (- n 1))
        \\      (fib (- n 2))))
    );
    try std.testing.expectEqual(
        55,
        try vm.evalStr(i64, "(fib 10)"),
    );
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
        ret = try self.runUnsafe();
    }
    return ret.toZig(T, self);
}

test evalStr {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    try vm.evalStr(void,
        \\ (defun fib (n)
        \\   (if (< n 2) (return n))
        \\   (+ (fib (- n 1))
        \\      (fib (- n 2))))
    );
    try std.testing.expectEqual(
        55,
        try vm.evalStr(i64, "(fib 10)"),
    );

    const val = try vm.evalStr(Val, "(+ 2 2)");
    try std.testing.expectFmt("4", "{any}", .{val.formatted(&vm)});
}

/// Run the garbage collector.
///
/// This reduces memory usage by cleaning up unused allocated
/// `Val`s. Any values provided through `external` will also not be
/// garbage collected.
pub fn runGc(self: *Vm, external: []const Val) !void {
    try self.objects.runGc(self, external);
}

test runGc {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();

    // .. do stuff
    const keep_me = try vm.evalStr(Val, "(list 1 2 3 4)");
    const dont_keep_me = try vm.evalStr(Val, "(list 5 6 7 8)");

    // Free unused memory.
    try vm.runGc(&.{keep_me});

    try std.testing.expectFmt("(1 2 3 4)", "{any}", .{keep_me.formatted(&vm)});
    try std.testing.expectFmt("(<invalid-list>)", "{any}", .{dont_keep_me.formatted(&vm)});
}

/// Run the virtual machine until some condition is met. You probably
/// mean to use something like `Vm.evalStr` instead.
///
/// * There are no more stack frames.
/// * The current stack frame has been popped. Earlier stack frames
///   will remain in tact.
pub fn runUnsafe(self: *Vm) Error!Val {
    const initial_stack_frames = self.stack.frames.items.len;
    if (initial_stack_frames == 0) {
        @setCold(true);
        return Val.init();
    }
    var return_value = Val.init();
    while (initial_stack_frames <= self.stack.frames.items.len) {
        const instruction = self.nextInstruction();
        if (try instruction.execute(self)) |v| {
            return_value = v;
        }
    }
    return return_value;
}

fn nextInstruction(self: Vm) Instruction {
    const frame = if (self.stack.currentFrame()) |f| f else return .{ .ret = {} };
    const is_ok = frame.next_instruction < frame.instructions.len;
    if (!is_ok) return .{ .ret = {} };
    const instruction = frame.instructions[frame.next_instruction];
    frame.next_instruction += 1;
    return instruction;
}
