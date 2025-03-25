const std = @import("std");
const testing = std.testing;

const AstBuilder = @import("AstBuilder.zig");
const ByteCodeFunction = @import("val.zig").ByteCodeFunction;
const Compiler = @import("Compiler.zig");
const Env = @import("Env.zig");
const FunctionError = @import("val.zig").FunctionError;
const FunctionVal = @import("val.zig").FunctionVal;
const Instruction = @import("instruction.zig").Instruction;
const InternedSymbol = @import("val.zig").InternedSymbol;
const ListVal = @import("val.zig").ListVal;
const Symbol = @import("Symbol.zig");
const Val = @import("val.zig").Val;
const builtins = @import("builtins.zig");

const Vm = @This();

options: Options,
env: Env,

pub const Options = struct {
    comptime stack_size: usize = 4096,
    allocator: std.mem.Allocator,
};

pub fn init(options: Options) !Vm {
    var vm = Vm{
        .options = options,
        .env = try Env.init(options.allocator, options.stack_size),
    };
    try builtins.registerAll(&vm);
    return vm;
}

pub fn registerGlobalFunction(self: *Vm, function: *const FunctionVal) !void {
    try self.registerGlobalValueByName(
        function.name,
        Val{ .function = function },
    );
}

pub fn registerGlobalValue(self: *Vm, symbol: InternedSymbol, value: Val) !void {
    try self.env.global.putValue(self.allocator(), symbol, value);
}

pub fn registerGlobalValueByName(self: *Vm, name: []const u8, value: Val) !void {
    const symbol = try self.env.objects.symbols.strToSymbol(
        self.allocator(),
        Symbol{ .quotes = 0, .name = name },
    );
    try self.registerGlobalValue(symbol, value);
}

pub fn allocator(self: *Vm) std.mem.Allocator {
    return self.options.allocator;
}

pub fn newSymbol(self: *Vm, str: []const u8) !InternedSymbol {
    return try self.env.objects.symbols.strToSymbol(
        self.options.allocator,
        try Symbol.init(str),
    );
}

pub fn evalStr(self: *Vm, source: []const u8) !Val {
    var ast_builder = AstBuilder.init(self, source);
    var compiler = try Compiler.init(self);
    defer compiler.deinit();
    var ret = Val{ .void = {} };
    while (try ast_builder.next()) |ast| {
        try compiler.compile(ast.expr);
        self.env.resetStacks();
        const stack_frame = Env.StackFrame{
            .instructions = compiler.currentExpr(),
            .stack_start = 0,
            .next_instruction = 0,
        };
        try self.env.stack_frames.append(self.allocator(), stack_frame);
        ret = try self.run();
    }
    return ret;
}

pub fn deinit(self: *Vm) void {
    self.env.deinit(self.options.allocator);
}

pub fn runGc(self: *Vm) !void {
    for (self.env.stack[0..self.env.stack_len]) |v| {
        self.env.objects.markReachable(v);
    }
    for (self.env.stack_frames.items) |stack_frame| {
        const bytecode_function = ByteCodeFunction{
            .name = "",
            .instructions = stack_frame.instructions,
        };
        bytecode_function.markChildren(&self.env.objects);
    }
    var globalsIter = self.env.global.values.valueIterator();
    while (globalsIter.next()) |v| {
        self.env.objects.markReachable(v.*);
    }
    try self.env.objects.sweepUnreachable(self.allocator());
}

fn run(self: *Vm) !Val {
    var return_value = Val{ .void = {} };
    while (self.env.nextInstruction()) |instruction| {
        switch (instruction) {
            .push => |val| try self.executePush(val),
            .eval => |n| try self.executeEval(n),
            .deref => |symbol| try self.executeDeref(symbol),
            .ret => return_value = try self.executeRet(),
        }
    }
    return return_value;
}

fn executePush(self: *Vm, val: Val) !void {
    try self.env.pushVal(val);
}

fn executeEval(self: *Vm, n: usize) !void {
    const function_idx = self.env.stack_len - n;
    const stack_start = function_idx + 1;
    const function_val = self.env.stack[function_idx];
    switch (function_val) {
        .function => |f| {
            try self.env.pushStackFrame(
                self.allocator(),
                Env.StackFrame{
                    .instructions = &[0]Instruction{},
                    .stack_start = stack_start,
                    .next_instruction = 0,
                },
            );
            const v = try f.*.function(self);
            self.env.stack[function_idx] = v;
            self.env.stack_len = function_idx + 1;
        },
        .bytecode_function => |bytecode_id| {
            const bytecode = self.env.objects.get(ByteCodeFunction, bytecode_id).?;
            try self.env.pushStackFrame(
                self.allocator(),
                Env.StackFrame{
                    .instructions = bytecode.instructions,
                    .stack_start = stack_start,
                    .next_instruction = 0,
                },
            );
        },
        else => return error.ValueNotCallable,
    }
}

fn executeDeref(self: *Vm, symbol: InternedSymbol) !void {
    const val = if (self.env.global.getValue(symbol)) |v| v else {
        if (self.env.objects.symbols.symbolToStr(symbol)) |name| {
            std.log.err("Symbol {s} not found.\n", .{name.name});
        } else {
            std.log.err("Symbol {any} not found.\n", .{symbol.id});
        }
        return error.SymbolNotFound;
    };
    try self.executePush(val);
}

fn executeRet(self: *Vm) !Val {
    const ret = try self.env.popStackFrame();
    try self.executePush(ret);
    return ret;
}
