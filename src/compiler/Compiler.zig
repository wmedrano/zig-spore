const std = @import("std");
const root = @import("../root.zig");

const Allocator = std.mem.Allocator;
const ByteCodeFunction = Val.ByteCodeFunction;
const Error = root.Error;
const Instruction = @import("../instruction.zig").Instruction;
const MacroExpander = @import("MacroExpander.zig");
const Symbol = Val.Symbol;
const Val = Vm.Val;
const Vm = root.Vm;
const builtin_macros = @import("../builtins/macros.zig");
const converters = @import("../converters.zig");

const Compiler = @This();

/// The virtual machine to compile for.
vm: *Vm,
/// The current set of instructions that have been constructed.
instructions: std.ArrayListUnmanaged(Instruction),
/// The symbol that is in the process of being defined.
define_context: []const u8,
/// The values on the local stack where the `nth` element of `locals`
/// is the `nth` element on the local stack.
locals: std.ArrayListUnmanaged([]const u8),
/// Object used to expand expressions with macros.
macro_expander: MacroExpander,

fn fieldType(comptime T: type, comptime field_name: []const u8) type {
    return @TypeOf(@field(@as(T, undefined), field_name));
}

/// Initialize a new compiler for a `Vm`.
pub fn init(vm: *Vm) !Compiler {
    return Compiler{
        .vm = vm,
        .instructions = .{},
        .define_context = "",
        .locals = .{},
        .macro_expander = try MacroExpander.init(vm),
    };
}

pub fn deinit(self: *Compiler) void {
    self.instructions.deinit(self.allocator());
    self.locals.deinit(self.allocator());
}

pub fn compile(self: *Compiler, expr: Val) ![]Instruction {
    const expanded_expr = try self.macro_expander.macroExpand(self.vm, expr);
    try self.resetAndCompile(&.{expanded_expr});
    return self.instructions.toOwnedSlice(self.allocator());
}

fn addLocal(self: *Compiler, name: []const u8) !void {
    try self.locals.append(self.allocator(), name);
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

fn resolveIdentifier(self: *Compiler, name: []const u8) !ResolvedName {
    var idx = self.locals.items.len;
    while (idx > 0) {
        idx -= 1;
        if (std.mem.eql(u8, self.locals.items[idx], name)) {
            return .{ .local = @intCast(idx) };
        }
    }
    const symbol = try Symbol.fromStr(name);
    return .{ .global = try symbol.intern(self.vm) };
}

fn resetAndCompile(self: *Compiler, exprs: []const Val) !void {
    self.instructions.clearRetainingCapacity();
    for (exprs) |expr| {
        try self.compileOne(expr);
    }
}

fn ownedInstructions(self: *Compiler) ![]Instruction {
    return try self.instructions.toOwnedSlice(self.allocator());
}

fn compileOne(self: *Compiler, expr: Val) Error!void {
    if (expr.is([]const Val)) {
        return self.compileTree(try expr.to([]const Val, self.vm));
    }
    if (expr.is(Symbol.Interned)) {
        return self.compileSymbol(try expr.to(Symbol.Interned, {}));
    }
    try self.instructions.append(self.allocator(), .{ .push = expr });
}

fn compileSymbol(self: *Compiler, symbol: Symbol.Interned) Error!void {
    if (symbol.quotes != 0) {
        return self.instructions.append(self.allocator(), .{
            .push = try Val.from(
                self.vm,
                Symbol.Interned{ .quotes = symbol.quotes - 1, .id = symbol.id },
            ),
        });
    }
    if (symbol.toSymbol(self.vm)) |named_symbol| {
        const resolved = try self.resolveIdentifier(named_symbol.name());
        return self.instructions.append(self.allocator(), resolved.toInstruction());
    }
    try self.instructions.append(self.allocator(), .{ .deref = symbol });
}

fn compileTree(self: *Compiler, nodes: []const Val) Error!void {
    const old_context = self.define_context;
    defer self.define_context = old_context;
    if (nodes.len == 0) {
        return Error.UnexpectedEmptyExpression;
    }
    if (nodes[0].is(Symbol.Interned)) {
        const leading_symbol = try nodes[0].to(Symbol.Interned, {});
        if (leading_symbol.eql(self.macro_expander.function)) {
            if (nodes.len < 3) {
                return Error.BadFunction;
            }
            const args = nodes[1].to([]const Val, self.vm) catch return Error.BadFunction;
            return self.compileFunction(args, nodes[2..]);
        } else if (leading_symbol.eql(self.macro_expander.@"%define")) {
            if (nodes.len != 3) return Error.BadDefine;
            return self.compileDefine(nodes[1], nodes[2]);
        } else if (leading_symbol.eql(self.macro_expander.@"if")) {
            switch (nodes.len) {
                3 => return self.compileIf(nodes[1], nodes[2], Val.init()),
                4 => return self.compileIf(nodes[1], nodes[2], nodes[3]),
                else => return Error.BadIf,
            }
        } else if (leading_symbol.eql(self.macro_expander.@"return")) {
            switch (nodes.len) {
                1 => return self.compileReturn(Val.init()),
                2 => return self.compileReturn(nodes[1]),
                else => return Error.BadArg,
            }
        }
    }
    for (nodes) |node| {
        try self.compileOne(node);
    }
    try self.instructions.append(
        self.allocator(),
        .{ .eval = @intCast(nodes.len) },
    );
}

fn compileReturn(self: *Compiler, expr: Val) Error!void {
    try self.compileOne(expr);
    try self.instructions.append(self.allocator(), .{ .ret = {} });
}

fn compileDefine(self: *Compiler, name: Val, expr: Val) Error!void {
    const old_context = self.define_context;
    defer self.define_context = old_context;
    if (!name.is(Symbol.Interned)) {
        return Error.BadDefine;
    }
    const interned_name = try name.to(Symbol.Interned, {});
    self.define_context = blk: {
        if (interned_name.toSymbol(self.vm)) |name_sym| {
            if (name_sym.quotes() > 1) {
                return Error.TooManyQuotes;
            }
            break :blk name_sym.name();
        } else {
            return Error.ObjectNotFound;
        }
    };
    try self.instructions.appendSlice(self.allocator(), &.{
        .{ .deref = self.macro_expander.@"%define" },
        .{ .push = interned_name.unquoted().toVal() },
    });
    try self.compileOne(expr);
    try self.instructions.append(self.allocator(), .{ .eval = 3 });
}

fn compileIf(self: *Compiler, pred: Val, true_branch: Val, false_branch: Val) Error!void {
    try self.compileOne(pred);
    const jump_if_idx = self.instructions.items.len;
    try self.instructions.append(
        self.allocator(),
        .{ .jump_if = 0 },
    );
    const false_branch_start = self.instructions.items.len;
    try self.compileOne(false_branch);
    const false_branch_end = self.instructions.items.len;
    const jump_idx = self.instructions.items.len;
    try self.instructions.append(
        self.allocator(),
        Instruction{ .jump = 0 },
    );
    const true_branch_start = self.instructions.items.len;
    try self.compileOne(true_branch);
    const true_branch_end = self.instructions.items.len;
    self.instructions.items[jump_if_idx] = .{
        .jump_if = @intCast(false_branch_end - false_branch_start + 1),
    };
    self.instructions.items[jump_idx] = .{
        .jump = @intCast(true_branch_end - true_branch_start),
    };
}

fn compileFunction(self: *Compiler, args: []const Val, exprs: []const Val) !void {
    var function_compiler = try Compiler.init(self.vm);
    defer function_compiler.deinit();
    for (args) |arg| {
        const arg_symbol = arg.to(Symbol, self.vm) catch return Error.BadFunction;
        if (arg_symbol.isQuoted()) return Error.BadFunction;
        try function_compiler.addLocal(arg_symbol.name());
    }
    try function_compiler.resetAndCompile(exprs);
    const bytecode = ByteCodeFunction{
        .name = try self.allocator().dupe(u8, self.define_context),
        .instructions = try function_compiler.ownedInstructions(),
        .args = @intCast(args.len),
    };
    const bytecode_id = try self.vm.objects.put(
        ByteCodeFunction,
        self.allocator(),
        bytecode,
    );
    try self.instructions.append(self.allocator(), .{ .push = bytecode_id.toVal() });
}

fn allocator(self: Compiler) std.mem.Allocator {
    return self.vm.allocator();
}
