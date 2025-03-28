const std = @import("std");

const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const function = @import("function.zig");

pub const InstructionTag = enum {
    push,
    eval,
    get_local,
    deref,
    jump_if,
    jump,
    ret,
};

pub const Instruction = union(InstructionTag) {
    push: Val,
    eval: u32,
    get_local: u32,
    deref: Symbol.Interned,
    jump_if: u32,
    jump: u32,
    ret,

    /// Get an instruction that can be pretty printed.
    pub fn formatted(self: Instruction, vm: *const Vm) FormattedInstruction {
        return .{ .instruction = self, .vm = vm };
    }

    /// Execute an instruction on `vm`.
    pub fn execute(self: Instruction, vm: *Vm) !?Val {
        const ret = blk: {
            switch (self) {
                .push => |val| {
                    try executePush(vm, val);
                    break :blk null;
                },
                .eval => |n| {
                    try executeEval(vm, n);
                    break :blk null;
                },
                .get_local => |idx| {
                    try executeGetLocal(vm, idx);
                    break :blk null;
                },
                .deref => |symbol| {
                    try executeDeref(vm, symbol);
                    break :blk null;
                },
                .jump_if => |n| {
                    executeJumpIf(vm, n);
                    break :blk null;
                },
                .jump => |n| {
                    executeJump(vm, n);
                    break :blk null;
                },
                .ret => break :blk try executeRet(vm),
            }
        };
        return ret;
    }

    fn executePush(vm: *Vm, val: Val) !void {
        try vm.pushStackVals(&.{val});
    }

    fn executeEval(vm: *Vm, n: u32) !void {
        if (n == 0) return function.Error.WrongArity;
        const function_idx = vm.stack_len - n;
        const stack_start = function_idx + 1;
        const function_val = vm.stack[function_idx];
        switch (function_val.repr) {
            .function => |f| {
                const result = try f.execute(vm, stack_start);
                vm.stack[function_idx] = result;
            },
            .bytecode_function => |bytecode_id| {
                const bytecode = vm.objects.get(function.ByteCodeFunction, bytecode_id).?;
                try bytecode.startExecute(vm, stack_start);
            },
            else => {
                if (vm.options.log) {
                    std.log.err("Value {any} not callable.", .{function_val.formatted(vm)});
                }
                return error.ValueNotCallable;
            },
        }
    }

    fn executeGetLocal(vm: *Vm, idx: u32) !void {
        const val = vm.localStack()[idx];
        try executePush(vm, val);
    }

    fn executeDeref(vm: *Vm, symbol: Symbol.Interned) !void {
        const val = if (vm.global.getValue(symbol)) |v| v else {
            if (vm.options.log) {
                if (vm.objects.string_interner.getString(symbol.id)) |name| {
                    std.log.err("Symbol {s} not found.\n", .{name});
                } else {
                    std.log.err("Symbol {any} not found.\n", .{symbol.id});
                }
            }
            return error.SymbolNotFound;
        };
        try executePush(vm, val);
    }

    fn executeJumpIf(vm: *Vm, n: u32) void {
        const val = vm.popStackVal();
        if (val.isTruthy()) {
            executeJump(vm, n);
        }
    }

    fn executeJump(vm: *Vm, n: u32) void {
        if (vm.stack_frames.items.len == 0) return;
        const stack_frame_idx = vm.stack_frames.items.len - 1;
        vm.stack_frames.items[stack_frame_idx].next_instruction += n;
    }

    fn executeRet(vm: *Vm) !Val {
        const ret = try vm.popStackFrame();
        if (vm.stack_len > 0) {
            vm.stack[vm.stack_len - 1] = ret;
        }
        return ret;
    }
};

pub const FormattedInstruction = struct {
    instruction: Instruction,
    vm: *const Vm,

    pub fn format(
        self: FormattedInstruction,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self.instruction) {
            .push => |v| try writer.print("(push {any})", .{v.formatted(self.vm)}),
            .eval => |n| try writer.print("(eval {d})", .{n}),
            .get_local => |n| try writer.print("(get-local {d})", .{n}),
            .deref => |interned_symbol| try writer.print("(deref {any})", .{interned_symbol.toVal().formatted(self.vm)}),
            .jump_if => |n| try writer.print("(jump-if {d})", .{n}),
            .jump => |n| try writer.print("(jump {d})", .{n}),
            .ret => try writer.print("(return)", .{}),
        }
    }
};
