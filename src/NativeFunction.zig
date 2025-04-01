//! Defines `NativeFunction`, which allows Zig functions to be called
//from within a `Vm`.
//!
//! Note: All members should live for the lifetime of the `Vm`.
const std = @import("std");

const Error = @import("root.zig").Error;
const Stack = @import("Stack.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const converters = @import("converters.zig");

const NativeFunction = @This();

/// The name of the function.
name: []const u8,
/// The function implementation that takes the `Vm` and returns a `Val`.
function: *const fn (*Vm) Error!Val,

/// Create a `NativeFunction` from a Zig function that takes a `*Vm`
/// and returns a `Val`.
///
/// Note: Its usually easier to use `withArgParser` instead of
/// extracting arguments out of `*Vm` manually.
///
/// # Example
///
/// ```zig
/// pub fn addTwo(vm: *Vm) Error!Val {
///     const args = vm.stack.local();
///     if (args.len != 1) return Error.WrongArity;
///     const arg = try args[0].toZig(i64, vm);
///     return Val.fromZig(vm, 2 + arg);
/// }
/// const my_func = NativeFunction.init("add-2", addTwo);
/// ```
pub fn init(comptime func_name: []const u8, comptime func: *const fn (*Vm) Error!Val) *const NativeFunction {
    const wrapped_function = struct {
        const native_function = NativeFunction{
            .name = func_name,
            .function = func,
        };
    };
    return &wrapped_function.native_function;
}

/// Create a `NativeFunction` from a Zig function. The first argument
/// of `func` must be a `*Vm` and the second must be a struct to store
/// all the parameters.
///
/// See `converters.parseAsArgs` for more details on argument parsing.
///
/// # Example
///
/// ```zig
/// pub fn addTwoInts(vm: *Vm, args: struct{a: i64, b: i64}) Error!Val {
///     return Val.fromZig(vm, args.a + args.b);
/// }
/// const my_func = NativeFunction.withArgParser("add-2-ints", addTwoInts);
/// ```
pub fn withArgParser(comptime func_name: []const u8, func: anytype) *const NativeFunction {
    const wrapped_function = struct {
        const native_function = NativeFunction{
            .name = func_name,
            .function = fnImpl,
        };

        fn fnImpl(vm: *Vm) Error!Val {
            const func_type = @typeInfo(@TypeOf(func));
            const arg_type = switch (func_type) {
                .Fn => |f| blk: {
                    if (f.params.len != 2 or f.params[0].type != *Vm) {
                        @compileError(
                            "withArgParser requires passing a `fn(*Vm, T) Error!Val` but passed a " ++
                                @typeName(func_type),
                        );
                    }
                    break :blk f.params[1].type.?;
                },
                else => @compileError(
                    "withArgParser requires passing a `fn(*Vm, T) Error!Val` but passed " ++
                        @typeName(func_type) ++ ".",
                ),
            };
            const args = try converters.parseAsArgs(arg_type, vm, vm.stack.local());
            return func(vm, args);
        }
    };
    return &wrapped_function.native_function;
}

/// Execute `self` on `vm` with `args`.
pub fn executeWith(self: NativeFunction, vm: *Vm, args: []const Val) !Val {
    const stack_start = vm.stack.items.len;
    try vm.stack.pushMany(args);
    return self.execute(vm, stack_start);
}

/// Execute `self` with the local stack starting at `stack_start`.
///
/// The result value is returned and the stack is truncated to end
/// (and exclude) `stack_start`.
pub fn execute(self: NativeFunction, vm: *Vm, stack_start: usize) !Val {
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
