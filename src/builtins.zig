const std = @import("std");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, &DEFINE_FUNCTION);
    try vm.global.registerFunction(vm, &PLUS_FUNCTION);
    try vm.global.registerFunction(vm, &STR_LEN_FUNCTION);
}

const DEFINE_FUNCTION = Val.FunctionVal{
    .name = "%define",
    .function = defineImpl,
};

const PLUS_FUNCTION = Val.FunctionVal{
    .name = "+",
    .function = plusImpl,
};

const STR_LEN_FUNCTION = Val.FunctionVal{
    .name = "str-len",
    .function = strLenImpl,
};

fn defineImpl(vm: *Vm) Val.FunctionError!Val {
    const args = vm.localStack();
    if (args.len != 2) {
        return Val.FunctionError.WrongArity;
    }
    const symbol = if (args[0].asInternedSymbol()) |s| s else return Val.FunctionError.WrongType;
    const value = args[1];
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

fn strLenImpl(vm: *Vm) Val.FunctionError!Val {
    const args = vm.localStack();
    if (args.len != 1) {
        return Val.FunctionError.WrongArity;
    }
    const str = if (args[0].asString(vm.*)) |s| s else return Val.FunctionError.WrongType;
    return Val.fromInt(@intCast(str.len));
}

test "str-len returns string length" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectEqual(
        Val.fromInt(4),
        try vm.evalStr("(str-len \"1234\")"),
    );
}
