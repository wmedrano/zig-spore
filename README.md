# Spore

An embeddable Lisp for Zig.

## Links

- [Zig Docs](https://wmedrano.github.io/zig-spore/)
- [Test Coverage](https://wmedrano.github.io/zig-spore/kcov/)

## Installation

1.  **Add as a Dependency:** Include Spore as a dependency in your `build.zig.dependencies` block:

    ```zig
    const spore = b.dependency("spore", .{
        .target = target,
        .optimize = optimize,
    });

    // Use it in your executable or library.
    exe.root_module.addImport("spore", spore.module("root"));
    exe.addPackagePath(.{}, spore.path(""));
    ```

2.  **Import:** Import the Spore module in your Zig code:

    ```zig
    const Vm = @import("spore").Vm;
    const Val = @import("spore").Val;
    const std = @import("std");
    ```

## Zig API

### Use Cases

-   **Initialize the VM:** Create a new `Vm` instance with an allocator.

    ```zig
    const Vm = @import("spore").Vm;
    var vm = try Vm.init(Vm.Options{ .allocator = std.testing.allocator });
    defer vm.deinit();
    ```

-   **Evaluate Spore Code:** Use `vm.evalStr` to execute Spore code. Specify the expected return type as a comptime parameter.

    ```zig
    const result = try vm.evalStr(i64, "(+ 20 22)");
    std.debug.print("Result: {any}\n", .{result}); // Output: Result: 42
    ```

-   **Register Functions:** Expose Zig functions to Spore using `NativeFunction`.

    ```zig
    const NativeFunction = @import("spore").Val.NativeFunction;
    fn addTwo(vm: *Vm, args: struct { num: i64 }) !Val {
        return Val.fromZig(vm, 2 + args.num);
    }

    try vm.global.registerFunction(&vm, NativeFunction.withArgParser("add-2", addTwo));
    const spore_result = try vm.evalStr(i64, "(add-2 8)");
    std.debug.print("Spore Result: {}\n", .{spore_result}); // Output: Spore Result: 10
    ```

### Example

```zig
const std = @import("std");
const Vm = @import("spore").Vm;
const Val = @import("spore").Val;
const NativeFunction = @import("spore").NativeFunction;
const Error = @import("spore").Error;

fn addTwo(vm: *Vm, args: struct { num: i64 }) Error!Val {
    return Val.fromZig(vm, 2 + args.num);
}

pub fn main() !void {
    var vm = try Vm.init(Vm.Options{ .allocator = std.heap.page_allocator });
    defer vm.deinit();

    try vm.global.registerFunction(
        &vm,
        NativeFunction.withArgParser("add-2", addTwo),
    );

    const result = try vm.evalStr(i64, "(add-2 8)");
    std.debug.print("Result: {}\n", .{result});
}
```

This example demonstrates initializing the VM, registering a Zig
function named `addTwo`, and calling it from Spore code.

## Spore Language Reference

Spore is a simple Lisp dialect designed for embedding in Zig projects.

Lisp is known for its parenthesized syntax, flexibility, and
metaprogramming capabilities. Embedding Spore lets you customize and
extend your Zig applications at runtime.

### Defining Values

Use `def` to define a new value.

```lisp
(def my-value 42)
(def my-string "hello")
```

### Defining Functions

Use `defun` to define a new function. The first argument is the
function name, the second is a list of arguments, and the remaining
arguments are the body of the function.

```lisp
(defun add (a b) (+ a b))
```

### Calling Functions

Call functions by placing the function name (or a symbol that resolves
to a function) first, followed by the arguments.

```lisp
(def x 10)
(add 10 20) ; Results in 30 if `add` is defined as above.
```

### `if` Statement

The `if` statement takes a condition, a "then" branch, and an optional
"else" branch.

```lisp
(if (> 10 5)
  (print "yes")
  (print "no")) ; prints "yes"

;; returns 42, prints "hello"
(if true
  (do
    (print "hello")
    42))
    
;; returns void
(if false 42)
```

### `when` Statement

The `when` statement is like an `if` statement without an "else"
branch. It executes the body if the condition is true.

```lisp
(when true
  (print "executing when")
  (print "this other statement also executes")
  (print "and so does any other statement"))

(when false
  (print "not executing when")
  (print "this also does not execute"))
```
