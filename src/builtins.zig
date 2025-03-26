const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, &DEFINE_FUNCTION);
    try vm.global.registerFunction(vm, &PLUS_FUNCTION);
}

const DEFINE_FUNCTION = Val.FunctionVal{
    .name = "%define",
    .function = defineImpl,
};

const PLUS_FUNCTION = Val.FunctionVal{
    .name = "+",
    .function = plusImpl,
};

fn defineImpl(vm: *Vm) Val.FunctionError!Val {
    const local_stack = vm.localStack();
    if (local_stack.len != 2) {
        return Val.FunctionError.WrongArity;
    }
    const symbol = if (local_stack[0].asInternedSymbol()) |s| s else return Val.FunctionError.WrongType;
    const value = local_stack[1];
    try vm.global.registerValue(vm, symbol, value);
    return Val.init();
}

fn plusImpl(vm: *Vm) Val.FunctionError!Val {
    var int_sum: i64 = 0;
    var float_sum: f64 = 0.0;
    var has_float = false;
    for (vm.localStack()) |v| {
        if (v.asInt()) |x| {
            int_sum += x;
        } else if (v.asFloat()) |x| {
            has_float = true;
            float_sum += x;
        } else {
            return Val.FunctionError.WrongType;
        }
    }
    if (has_float) {
        const int_sum_as_float: f64 = @floatFromInt(int_sum);
        return Val.fromFloat(float_sum + int_sum_as_float);
    }
    return Val.fromInt(int_sum);
}
