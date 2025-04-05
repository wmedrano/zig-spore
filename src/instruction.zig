const std = @import("std");

const ByteCodeFunction = Val.ByteCodeFunction;
const Error = @import("root.zig").Error;
const Symbol = Val.Symbol;
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

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
    pub fn execute(self: Instruction, vm: *Vm) Error!?Val {
        switch (self) {
            .push => |val| {
                try vm.stack.push(val);
                return null;
            },
            .eval => |n| {
                try executeEval(vm, n);
                return null;
            },
            .get_local => |idx| {
                try executeGetLocal(vm, idx);
                return null;
            },
            .deref => |symbol| {
                try executeDeref(vm, symbol);
                return null;
            },
            .jump_if => |n| {
                executeJumpIf(vm, n);
                return null;
            },
            .jump => |n| {
                executeJump(vm, n);
                return null;
            },
            .ret => return try executeRet(vm),
        }
    }

    fn executeEval(vm: *Vm, n: u32) Error!void {
        if (n == 0) return Error.WrongArity;
        const function_idx = vm.stack.items.len - n;
        const stack_start = function_idx + 1;
        const function_val = vm.stack.items[function_idx];
        switch (function_val._repr) {
            .function => |f| {
                const result = try f.execute(vm, stack_start);
                vm.stack.items[function_idx] = result;
            },
            .bytecode_function => |bytecode_id| {
                const bytecode = try vm.objects.get(ByteCodeFunction, bytecode_id);
                try bytecode.startExecute(vm, stack_start);
            },
            else => {
                if (vm.options.log) {
                    std.log.err("Value {any} not callable.", .{function_val.formatted(vm)});
                }
                return Error.ExpectedFunction;
            },
        }
    }

    fn executeGetLocal(vm: *Vm, idx: u32) !void {
        const val = vm.stack.local()[idx];
        try vm.stack.push(val);
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
            return Error.SymbolNotFound;
        };
        try vm.stack.push(val);
    }

    fn executeJumpIf(vm: *Vm, n: u32) void {
        const val = vm.stack.pop();
        if (val.isTruthy()) {
            executeJump(vm, n);
        }
    }

    fn executeJump(vm: *Vm, n: u32) void {
        if (vm.stack.frames.items.len == 0) return;
        const stack_frame_idx = vm.stack.frames.items.len - 1;
        vm.stack.frames.items[stack_frame_idx].next_instruction += n;
    }

    fn executeRet(vm: *Vm) !Val {
        const ret = try vm.stack.popFrame();
        if (vm.stack.items.len > 0) {
            vm.stack.items[vm.stack.items.len - 1] = ret;
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
