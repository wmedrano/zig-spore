const std = @import("std");

const ByteCodeFunction = @import("../ByteCodeFunction.zig");
const Error = @import("../error.zig").Error;
const NativeFunction = @import("../NativeFunction.zig");
const Symbol = @import("../Symbol.zig");
const Val = @import("../Val.zig");
const Vm = @import("../Vm.zig");
const converters = @import("../converters.zig");

pub fn registerAll(vm: *Vm) !void {
    try vm.global.registerFunction(vm, NativeFunction.withArgParser("function-bytecode", functionBytecodeFn));
}

fn functionBytecodeFn(vm: *Vm, args: struct { func: Val }) Error!Val {
    const func = try args.func.toZig(ByteCodeFunction, vm);
    var ret = try vm.allocator().alloc(Val, func.instructions.len);
    defer vm.allocator().free(ret);
    const symbols = try converters.symbolTable(vm, struct {
        push: Symbol.Interned,
        eval: Symbol.Interned,
        @"get-local": Symbol.Interned,
        deref: Symbol.Interned,
        @"jump-if": Symbol.Interned,
        jump: Symbol.Interned,
        ret: Symbol.Interned,
    });
    for (0..func.instructions.len, func.instructions) |idx, instruction| {
        const code = switch (instruction) {
            .push => try Val.fromZig(vm, symbols.push),
            .eval => try Val.fromZig(vm, symbols.eval),
            .get_local => try Val.fromZig(vm, symbols.@"get-local"),
            .deref => try Val.fromZig(vm, symbols.deref),
            .jump_if => try Val.fromZig(vm, symbols.@"jump-if"),
            .jump => try Val.fromZig(vm, symbols.jump),
            .ret => try Val.fromZig(vm, symbols.ret),
        };
        const data: ?Val = switch (instruction) {
            .push => |v| v,
            .eval => |n| try Val.fromZig(vm, @as(i64, @intCast(n))),
            .get_local => |n| try Val.fromZig(vm, @as(i64, @intCast(n))),
            .deref => |sym| sym.toVal(),
            .jump_if => |n| try Val.fromZig(vm, @as(i64, n)),
            .jump => |n| try Val.fromZig(vm, @as(i64, n)),
            .ret => null,
        };
        ret[idx] = if (data) |d|
            try Val.fromZig(vm, @as([]const Val, &[_]Val{ code, d }))
        else
            try Val.fromZig(vm, @as([]const Val, &[_]Val{code}));
    }
    return try Val.fromZig(vm, ret);
}

test "function-bytecode returns bytecode representation" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.evalStr(void, "(defun foo (x) (if x (return 1)) (bar))");
    const actual = try vm.evalStr(Val, "(function-bytecode foo)");
    try std.testing.expect(actual.is([]const Val));
    try std.testing.expectFmt(
        "((get-local 0) (jump-if 2) (push (<void>)) (jump 2) (push 1) (ret) (deref bar) (eval 1))",
        "{any}",
        .{actual.formatted(&vm)},
    );
}
