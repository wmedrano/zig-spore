const std = @import("std");

const Instruction = @import("instruction.zig").Instruction;
const ObjectManager = @import("ObjectManager.zig");
const Stack = @import("Stack.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const function = @import("function.zig");

pub const Error = error{
    BadArg,
    BadDefine,
    BadFunction,
    BadIf,
    BadString,
    BadWhen,
    EmptyAtom,
    EmptyKey,
    EmptySymbol,
    ExpectedIdentifier,
    NotImplemented,
    ObjectNotFound,
    StackFrameUnderflow,
    StackOverflow,
    TooManyQuotes,
    UnexpectedCloseParen,
    UnexpectedEmptyExpression,
    ValueAlreadyDefined,
    WrongArity,
    WrongType,
} || std.mem.Allocator.Error;

pub const ByteCodeFunction = struct {
    name: []const u8,
    instructions: []const Instruction,
    args: u32,

    pub fn garbageCollect(self: *ByteCodeFunction, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.instructions);
    }

    pub fn markChildren(self: ByteCodeFunction, obj: *ObjectManager) void {
        markInstructions(self.instructions, obj);
    }

    pub fn markInstructions(instructions: []const Instruction, obj: *ObjectManager) void {
        for (instructions) |instruction| {
            switch (instruction) {
                .push => |v| obj.markReachable(v),
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
        if (self.args != arg_count) return function.Error.WrongArity;
        try vm.stack.pushFrame(
            Stack.Frame{
                .instructions = self.instructions,
                .stack_start = stack_start,
                .next_instruction = 0,
            },
        );
    }
};

/// Contains a Zig function that can be evaluated within a `Vm`.
///
/// Note: All members should live for the lifetime of the `Vm`.
pub const FunctionVal = struct {
    /// The name of the function.
    name: []const u8,
    /// The function implementation that takes the `Vm` and returns a `Val`.
    function: *const fn (*Vm) Error!Val,

    /// Create a new function from a Zig function.
    ///
    /// Example:
    /// ```zig
    ///   pub fn addTwo(vm: *Vm) Val.FunctionError!Val {
    ///       const args = vm.stack.local();
    ///       if (args.len != 1) return Val.FunctionError.WrongArity;
    ///       const arg = try args[0].toZig(i64, vm);
    ///       return Val.fromZig(i64, vm, 2 + arg);
    ///   }
    /// const my_func = FunctionVal.init("add-2", addTwo);
    /// ```
    pub fn init(comptime func_name: []const u8, comptime func: anytype) *const FunctionVal {
        const wrapped_function = struct {
            const function = FunctionVal{
                .name = func_name,
                .function = func,
            };
        };
        return &wrapped_function.function;
    }

    /// Execute `self` on`vm` with `args`.
    pub fn executeWith(self: FunctionVal, vm: *Vm, args: []const Val) !Val {
        const stack_start = vm.stack.items.len;
        try vm.stack.pushMany(args);
        return self.execute(vm, stack_start);
    }

    /// Execute `self` with the local stack starting at `stack_start`.
    ///
    /// The result value is returned and the stack is truncated to end
    /// (and exclude) `stack_start`.
    pub fn execute(self: FunctionVal, vm: *Vm, stack_start: usize) !Val {
        try vm.stack.pushFrame(
            Stack.Frame{
                .instructions = &.{},
                .stack_start = stack_start,
                .next_instruction = 0,
            },
        );
        const result = try self.function(vm);
        vm.stack.items.len = stack_start;
        _ = try vm.stack.popFrame();
        return result;
    }
};
