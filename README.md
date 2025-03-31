# Spore

An embeddable Lisp for Zig.

## Links

- [Zig Docs](https://wmedrano.github.io/zig-spore/)
- [Test Coverage](https://wmedrano.github.io/zig-spore/kcov/)

## Example

```zig
fn addTwoFn(vm: *Vm, args: struct { num: i64 }) Error!Val {
    return Val.fromZig(vm, 2 + args.num);
}

test "can eval custom fuction" {
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    try vm.global.registerFunction(
        &vm,
        NativeFunction.withArgParser("add-2", addTwoFn),
    );
    try std.testing.expectEqual(
        10,
        try vm.evalStr(i64, "(add-2 8)"),
    );
}
```
