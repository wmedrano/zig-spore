const std = @import("std");

const Allocator = std.mem.Allocator;
const Instruction = @import("instruction.zig").Instruction;
const Symbol = @import("Symbol.zig");
const Val = @import("Val.zig");
const Vm = @import("Vm.zig");
const builtin_macros = @import("builtin_macros.zig");
const converters = @import("converters.zig");
const function = @import("function.zig");

const Compiler = @This();

vm: *Vm,
instructions: std.ArrayListUnmanaged(Instruction),
// The symbol that is in thep process of being defined.
define_context: []const u8,
locals: std.ArrayListUnmanaged([]const u8),
symbols: struct {
    @"%define": Symbol.Interned,
    def: Symbol.Interned,
    defun: Symbol.Interned,
    function: Symbol.Interned,
    do: Symbol.Interned,
    @"if": Symbol.Interned,
    when: Symbol.Interned,
},

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
        .symbols = try converters.symbolTable(vm, fieldType(Compiler, "symbols")),
    };
}

pub fn deinit(self: *Compiler) void {
    self.instructions.deinit(self.allocator());
    self.locals.deinit(self.allocator());
}

pub fn compile(self: *Compiler, expr: Val) ![]Instruction {
    const macro_expanded_expr = if (try self.macroExpand(expr)) |v| v else expr;
    try self.resetAndCompile(&.{macro_expanded_expr});
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

fn macroExpand(self: *Compiler, ast: Val) !?Val {
    const expr = ast.toZig([]const Val, self.vm) catch return null;
    if (expr.len == 0) {
        return null;
    }
    // TODO: Verify correctness of macro expansion order.
    if (try self.macroExpandSubexpressions(expr)) |v| {
        return if (try self.macroExpand(v)) |x| x else v;
    }
    const leading_symbol = if (expr[0].asInternedSymbol()) |x| x else return null;
    const macro_fn: ?*const function.FunctionVal = if (leading_symbol.eql(self.symbols.def))
        function.FunctionVal.init("def", builtin_macros.defMacro)
    else if (leading_symbol.eql(self.symbols.defun))
        function.FunctionVal.init("defun", builtin_macros.defunMacro)
    else if (leading_symbol.eql(self.symbols.when))
        function.FunctionVal.init("when", builtin_macros.whenMacro)
    else
        null;
    if (macro_fn) |f| {
        const expanded = try f.executeWith(self.vm, expr[1..]);
        return if (try self.macroExpand(expanded)) |x| x else expanded;
    }
    return null;
}

fn macroExpandSubexpressions(self: *Compiler, expr: []const Val) function.Error!?Val {
    var expandedExpr: ?[]Val = null;
    defer if (expandedExpr) |v| self.allocator().free(v);
    for (expr, 0..expr.len) |sub_expr, idx| {
        if (try self.macroExpand(sub_expr)) |v| {
            if (expandedExpr) |_| {} else {
                expandedExpr = try self.allocator().dupe(Val, expr);
            }
            expandedExpr.?[idx] = v;
        }
    }
    if (expandedExpr) |vals| {
        const list_val = try Val.fromZig(self.vm, vals);
        return list_val;
    }
    return null;
}

fn compileOne(self: *Compiler, unexpanded_ast: Val) function.Error!void {
    const ast = if (try self.macroExpand(unexpanded_ast)) |v| v else unexpanded_ast;
    switch (ast.repr) {
        .list => |list_id| {
            const list = self.vm.objects.get(Val.List, list_id);
            try self.compileTree(list.?.list);
        },
        .symbol => |symbol| try self.compileSymbol(symbol),
        else => try self.instructions.append(
            self.allocator(),
            Instruction{ .push = ast },
        ),
    }
}

fn compileSymbol(self: *Compiler, symbol: Symbol.Interned) function.Error!void {
    if (symbol.quotes != 0) {
        try self.instructions.append(
            self.allocator(),
            Instruction{
                .push = try Val.fromZig(
                    self.vm,
                    Symbol.Interned{ .quotes = symbol.quotes - 1, .id = symbol.id },
                ),
            },
        );
        return;
    }
    if (symbol.toSymbol(self.vm)) |named_symbol| {
        const resolved = try self.resolveIdentifier(named_symbol.name);
        try self.instructions.append(
            self.allocator(),
            resolved.toInstruction(),
        );
        return;
    }
    try self.instructions.append(
        self.allocator(),
        Instruction{ .deref = symbol },
    );
}

fn compileTree(self: *Compiler, nodes: []const Val) function.Error!void {
    const old_context = self.define_context;
    defer self.define_context = old_context;
    if (nodes.len == 0) {
        return function.Error.UnexpectedEmptyExpression;
    }
    if (nodes[0].asInternedSymbol()) |leading_symbol| {
        if (leading_symbol.eql(self.symbols.function)) {
            if (nodes.len < 3) {
                return function.Error.BadFunction;
            }
            const args = nodes[1].toZig([]const Val, self.vm) catch return function.Error.BadFunction;
            return self.compileFunction(args, nodes[2..]);
        } else if (leading_symbol.eql(self.symbols.@"%define")) {
            if (nodes.len < 2) {
                return function.Error.BadDefine;
            }
            if (nodes[1].asInternedSymbol()) |s| {
                self.define_context = blk: {
                    if (s.toSymbol(self.vm)) |name| {
                        if (name.quotes > 1) {
                            return function.Error.TooManyQuotes;
                        }
                        break :blk name.name;
                    } else {
                        return function.Error.ObjectNotFound;
                    }
                };
            }
        } else if (leading_symbol.eql(self.symbols.@"if")) {
            switch (nodes.len) {
                3 => return self.compileIf(nodes[1], nodes[2], Val.init()),
                4 => return self.compileIf(nodes[1], nodes[2], nodes[3]),
                else => return function.Error.BadIf,
            }
        }
    }
    for (nodes) |node| {
        try self.compileOne(node);
    }
    try self.instructions.append(
        self.allocator(),
        Instruction{ .eval = @intCast(nodes.len) },
    );
}

fn compileIf(self: *Compiler, pred: Val, true_branch: Val, false_branch: Val) function.Error!void {
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
        const arg_symbol = arg.toZig(Symbol, self.vm) catch return function.Error.BadFunction;
        if (arg_symbol.quotes != 0) return function.Error.BadFunction;
        try function_compiler.addLocal(arg_symbol.name);
    }
    try function_compiler.resetAndCompile(exprs);
    const bytecode = function.ByteCodeFunction{
        .name = try self.allocator().dupe(u8, self.define_context),
        .instructions = try function_compiler.ownedInstructions(),
        .args = @intCast(args.len),
    };
    const bytecode_id = try self.vm.objects.put(function.ByteCodeFunction, self.allocator(), bytecode);
    try self.instructions.append(
        self.allocator(),
        Instruction{ .push = bytecode_id.toVal() },
    );
}

fn allocator(self: *Compiler) std.mem.Allocator {
    return self.vm.allocator();
}
