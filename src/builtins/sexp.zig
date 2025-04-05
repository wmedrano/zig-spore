const std = @import("std");

const SexpBuilder = @import("../compiler/SexpBuilder.zig");
const Error = @import("../error.zig").Error;
const NativeFunction = Val.NativeFunction;
const Val = Vm.Val;
const Vm = @import("../Vm.zig");
const converters = @import("../converters.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("str->sexps", strToSexpsFn));
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("str->sexp", strToSexpFn));
}

pub fn strToSexpsFn(vm: *Vm, args: struct { str: []const u8 }) Error!Val {
    var sexp_builder = SexpBuilder.init(args.str);
    const sexps = try sexp_builder.parseAll(vm, vm.allocator());
    return Val.fromOwnedList(vm, sexps);
}

pub fn strToSexpFn(vm: *Vm, args: struct { str: []const u8 }) Error!Val {
    var sexp_builder = SexpBuilder.init(args.str);
    const sexp = if (try sexp_builder.next(vm)) |expr| expr else return Val.init();
    if (try sexp_builder.next(vm)) |_| return Error.BadArg;
    return sexp;
}

test "str->sexp produces s-expression" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("(str->sexp \"   (+ 1 (foo 2 3 :key ''quoted))    \")");
    try std.testing.expectFmt(
        "(+ 1 (foo 2 3 :key ''quoted))",
        "{any}",
        .{actual.formatted(&vm)},
    );
}

test "str->sexp on empty string produces void" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.to(void, try vm.evalStr("(str->sexp \"\")"));
}

test "str->sexp with multiple sexps returns error" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try std.testing.expectError(
        Error.BadArg,
        vm.evalStr("(str->sexp \"(+ 1 2) (+ 3 4)\")"),
    );
}
