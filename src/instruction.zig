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
        try vm.pushStackVal(val);
    }

    fn executeEval(vm: *Vm, n: u32) !void {
        if (n == 0) return function.Error.WrongArity;
        const function_idx = vm.stack_len - n;
        const stack_start = function_idx + 1;
        switch (vm.stack[function_idx].repr) {
            .function => |f| {
                const result = try f.execute(vm, stack_start);
                vm.stack[function_idx] = result;
            },
            .bytecode_function => |bytecode_id| {
                const bytecode = vm.objects.get(function.ByteCodeFunction, bytecode_id).?;
                try bytecode.startExecute(vm, stack_start);
            },
            else => return error.ValueNotCallable,
        }
    }

    fn executeGetLocal(vm: *Vm, idx: u32) !void {
        const val = vm.localStack()[idx];
        try executePush(vm, val);
    }

    fn executeDeref(vm: *Vm, symbol: Symbol.Interned) !void {
        const val = if (vm.global.getValue(symbol)) |v| v else {
            if (vm.objects.string_interner.getString(symbol.id)) |name| {
                std.log.err("Symbol {s} not found.\n", .{name});
            } else {
                std.log.err("Symbol {any} not found.\n", .{symbol.id});
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
        try executePush(vm, ret);
        return ret;
    }
};
