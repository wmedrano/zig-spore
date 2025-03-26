const std = @import("std");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

pub const InstructionTag = enum { push, eval, deref, ret };

pub const Instruction = union(InstructionTag) {
    push: Val,
    eval: u32,
    deref: Val.InternedSymbol,
    ret,

    pub fn execute(self: Instruction, vm: *Vm) !?Val {
        switch (self) {
            .push => |val| {
                try executePush(vm, val);
                return null;
            },
            .eval => |n| {
                try executeEval(vm, n);
                return null;
            },
            .deref => |symbol| {
                try executeDeref(vm, symbol);
                return null;
            },
            .ret => return try executeRet(vm),
        }
    }

    fn executePush(vm: *Vm, val: Val) !void {
        try vm.pushStackVal(val);
    }

    fn executeEval(vm: *Vm, n: usize) !void {
        const function_idx = vm.stack_len - n;
        const stack_start = function_idx + 1;
        const function_val = vm.stack[function_idx];
        switch (function_val.repr) {
            .function => |f| {
                try vm.pushStackFrame(
                    Vm.StackFrame{
                        .instructions = &[0]Instruction{},
                        .stack_start = stack_start,
                        .next_instruction = 0,
                    },
                );
                const v = try f.*.function(vm);
                vm.stack[function_idx] = v;
                vm.stack_len = function_idx + 1;
            },
            .bytecode_function => |bytecode_id| {
                const bytecode = vm.objects.get(Val.ByteCodeFunction, bytecode_id).?;
                try vm.pushStackFrame(
                    Vm.StackFrame{
                        .instructions = bytecode.instructions,
                        .stack_start = stack_start,
                        .next_instruction = 0,
                    },
                );
            },
            else => return error.ValueNotCallable,
        }
    }

    fn executeDeref(vm: *Vm, symbol: Val.InternedSymbol) !void {
        const val = if (vm.global.getValue(symbol)) |v| v else {
            if (vm.objects.symbols.internedSymbolToSymbol(symbol)) |name| {
                std.log.err("Symbol {s} not found.\n", .{name.name});
            } else {
                std.log.err("Symbol {any} not found.\n", .{symbol.id});
            }
            return error.SymbolNotFound;
        };
        try executePush(vm, val);
    }

    fn executeRet(vm: *Vm) !Val {
        const ret = try vm.popStackFrame();
        try executePush(vm, ret);
        return ret;
    }
};
