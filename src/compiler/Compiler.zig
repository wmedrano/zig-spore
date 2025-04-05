const std = @import("std");
const root = @import("../root.zig");

const Allocator = std.mem.Allocator;
const ByteCodeFunction = Val.ByteCodeFunction;
const Error = root.Error;
const Instruction = @import("../instruction.zig").Instruction;
const Symbol = Val.Symbol;
const Val = Vm.Val;
const Vm = root.Vm;
const builtin_macros = @import("../builtins/macros.zig");
const converters = @import("../converters.zig");
const macro_expand = @import("macro_expand.zig");

const Compiler = @This();

/// The current set of instructions that have been constructed.
instructions: std.ArrayListUnmanaged(Instruction) = .{},
/// The symbol that is in the process of being defined.
define_context: []const u8 = "",
/// The values on the local stack where the `nth` element of `locals`
/// is the `nth` element on the local stack.
locals: std.ArrayListUnmanaged([]const u8) = .{},

/// Deinitializes the compiler, freeing any allocated memory.
pub fn deinit(self: *Compiler, vm: *Vm) void {
    self.instructions.deinit(vm.allocator());
    self.locals.deinit(vm.allocator());
}

/// Compiles a `Val` expression into a slice of `Instruction`s.
///
/// Expands any macros in the expression before compiling.
pub fn compile(self: *Compiler, vm: *Vm, expr: Val) ![]Instruction {
    const expanded_expr = try macro_expand.expand(vm, expr);
    try self.resetAndCompile(vm, &.{expanded_expr});
    return self.instructions.toOwnedSlice(vm.allocator());
}

fn addLocal(self: *Compiler, vm: *Vm, name: []const u8) !void {
    try self.locals.append(vm.allocator(), name);
}

const ResolvedName = union(enum) {
    local: u32,
    global: Symbol.Interned,

    fn toInstruction(self: ResolvedName) Instruction {
        switch (self) {
            .local => |idx| return .{ .get_local = idx },
            .global => |sym| return .{ .deref = sym },
        }
    }
};

fn resolveIdentifier(self: *Compiler, vm: *Vm, name: []const u8) !ResolvedName {
    var idx = self.locals.items.len;
    while (idx > 0) {
        idx -= 1;
        if (std.mem.eql(u8, self.locals.items[idx], name)) {
            return .{ .local = @intCast(idx) };
        }
    }
    const symbol = try Symbol.fromStr(name);
    return .{ .global = try symbol.intern(vm) };
}

fn resetAndCompile(self: *Compiler, vm: *Vm, exprs: []const Val) !void {
    self.instructions.clearRetainingCapacity();
    for (exprs) |expr| {
        try self.compileOne(vm, expr);
    }
}

fn ownedInstructions(self: *Compiler, vm: *Vm) ![]Instruction {
    return try self.instructions.toOwnedSlice(vm.allocator());
}

fn compileOne(self: *Compiler, vm: *Vm, expr: Val) Error!void {
    if (expr.is([]const Val)) {
        return self.compileTree(vm, try expr.to([]const Val, vm));
    }
    if (expr.is(Symbol.Interned)) {
        return self.compileSymbol(vm, try expr.to(Symbol.Interned, {}));
    }
    try self.instructions.append(vm.allocator(), .{ .push = expr });
}

fn compileSymbol(self: *Compiler, vm: *Vm, symbol: Symbol.Interned) Error!void {
    if (symbol.quotes != 0) {
        return self.instructions.append(vm.allocator(), .{
            .push = try Val.from(
                vm,
                Symbol.Interned{ .quotes = symbol.quotes - 1, .id = symbol.id },
            ),
        });
    }
    if (symbol.toSymbol(vm)) |named_symbol| {
        const resolved = try self.resolveIdentifier(vm, named_symbol.name());
        return self.instructions.append(vm.allocator(), resolved.toInstruction());
    }
    try self.instructions.append(vm.allocator(), .{ .deref = symbol });
}

fn compileTree(self: *Compiler, vm: *Vm, nodes: []const Val) Error!void {
    const old_context = self.define_context;
    defer self.define_context = old_context;
    if (nodes.len == 0) {
        return Error.UnexpectedEmptyExpression;
    }
    if (nodes[0].is(Symbol.Interned)) {
        const leading_symbol = try nodes[0].to(Symbol.Interned, {});
        if (leading_symbol.eql(vm.common_symbols.function)) {
            if (nodes.len < 3) {
                return Error.BadFunction;
            }
            const args = nodes[1].to([]const Val, vm) catch return Error.BadFunction;
            return self.compileFunction(vm, args, nodes[2..]);
        } else if (leading_symbol.eql(vm.common_symbols.@"%define")) {
            if (nodes.len != 3) return Error.BadDefine;
            return self.compileDefine(vm, nodes[1], nodes[2]);
        } else if (leading_symbol.eql(vm.common_symbols.@"if")) {
            switch (nodes.len) {
                3 => return self.compileIf(vm, nodes[1], nodes[2], Val.init()),
                4 => return self.compileIf(vm, nodes[1], nodes[2], nodes[3]),
                else => return Error.BadIf,
            }
        } else if (leading_symbol.eql(vm.common_symbols.@"return")) {
            switch (nodes.len) {
                1 => return self.compileReturn(vm, Val.init()),
                2 => return self.compileReturn(vm, nodes[1]),
                else => return Error.BadArg,
            }
        }
    }
    for (nodes) |node| {
        try self.compileOne(vm, node);
    }
    try self.instructions.append(
        vm.allocator(),
        .{ .eval = @intCast(nodes.len) },
    );
}

fn compileReturn(self: *Compiler, vm: *Vm, expr: Val) Error!void {
    try self.compileOne(vm, expr);
    try self.instructions.append(vm.allocator(), .{ .ret = {} });
}

fn compileDefine(self: *Compiler, vm: *Vm, name: Val, expr: Val) Error!void {
    const old_context = self.define_context;
    defer self.define_context = old_context;
    if (!name.is(Symbol.Interned)) {
        return Error.BadDefine;
    }
    const interned_name = try name.to(Symbol.Interned, {});
    self.define_context = blk: {
        if (interned_name.toSymbol(vm)) |name_sym| {
            if (name_sym.quotes() > 1) {
                return Error.TooManyQuotes;
            }
            break :blk name_sym.name();
        } else {
            return Error.ObjectNotFound;
        }
    };
    try self.instructions.appendSlice(vm.allocator(), &.{
        .{ .deref = vm.common_symbols.@"%define" },
        .{ .push = interned_name.unquoted().toVal() },
    });
    try self.compileOne(vm, expr);
    try self.instructions.append(vm.allocator(), .{ .eval = 3 });
}

fn compileIf(self: *Compiler, vm: *Vm, pred: Val, true_branch: Val, false_branch: Val) Error!void {
    try self.compileOne(vm, pred);
    const jump_if_idx = self.instructions.items.len;
    try self.instructions.append(
        vm.allocator(),
        .{ .jump_if = 0 },
    );
    const false_branch_start = self.instructions.items.len;
    try self.compileOne(vm, false_branch);
    const false_branch_end = self.instructions.items.len;
    const jump_idx = self.instructions.items.len;
    try self.instructions.append(
        vm.allocator(),
        Instruction{ .jump = 0 },
    );
    const true_branch_start = self.instructions.items.len;
    try self.compileOne(vm, true_branch);
    const true_branch_end = self.instructions.items.len;
    self.instructions.items[jump_if_idx] = .{
        .jump_if = @intCast(false_branch_end - false_branch_start + 1),
    };
    self.instructions.items[jump_idx] = .{
        .jump = @intCast(true_branch_end - true_branch_start),
    };
}

fn compileFunction(self: *Compiler, vm: *Vm, args: []const Val, exprs: []const Val) !void {
    var function_compiler = Compiler{};
    defer function_compiler.deinit(vm);
    for (args) |arg| {
        const arg_symbol = arg.to(Symbol, vm) catch return Error.BadFunction;
        if (arg_symbol.isQuoted()) return Error.BadFunction;
        try function_compiler.addLocal(vm, arg_symbol.name());
    }
    try function_compiler.resetAndCompile(vm, exprs);
    const bytecode = ByteCodeFunction{
        .name = try vm.allocator().dupe(u8, self.define_context),
        .instructions = try function_compiler.ownedInstructions(vm),
        .args = @intCast(args.len),
    };
    const bytecode_id = try vm.objects.put(
        ByteCodeFunction,
        vm.allocator(),
        bytecode,
    );
    try self.instructions.append(vm.allocator(), .{ .push = bytecode_id.toVal() });
}
