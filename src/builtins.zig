const FunctionError = @import("val.zig").FunctionError;
const FunctionVal = @import("val.zig").FunctionVal;
const Val = @import("val.zig").Val;
const Vm = @import("vm.zig").Vm;

pub fn registerAll(vm: *Vm) !void {
    try vm.registerGlobalFunction(&DEFINE_FUNCTION);
    try vm.registerGlobalFunction(&PLUS_FUNCTION);
}

const DEFINE_FUNCTION = FunctionVal{
    .name = "%define",
    .function = defineImpl,
};

const PLUS_FUNCTION = FunctionVal{
    .name = "+",
    .function = plusImpl,
};

fn defineImpl(vm: *Vm) FunctionError!Val {
    const local_stack = vm.env.localStack();
    if (local_stack.len != 2) {
        return FunctionError.WrongArity;
    }
    const symbol = switch (local_stack[0]) {
        .symbol => |s| s,
        else => return FunctionError.WrongType,
    };
    const value = local_stack[1];
    try vm.env.global.putValue(vm.allocator(), symbol, value);
    return Val{ .void = {} };
}

fn plusImpl(vm: *Vm) FunctionError!Val {
    var int_sum: i64 = 0;
    var float_sum: f64 = 0.0;
    var has_float = false;
    for (vm.env.localStack()) |v| {
        switch (v) {
            .int => |x| int_sum += x,
            .float => |x| {
                float_sum += x;
                has_float = true;
            },
            else => return FunctionError.WrongType,
        }
    }
    if (has_float) {
        const int_sum_as_float: f64 = @floatFromInt(int_sum);
        return Val{ .float = float_sum + int_sum_as_float };
    }
    return Val{ .int = int_sum };
}
