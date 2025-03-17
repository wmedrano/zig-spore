const std = @import("std");
const testing = std.testing;

const AstBuilder = @import("ast.zig").AstBuilder;
const Compiler = @import("compiler.zig").Compiler;
const Env = @import("env.zig").Env;
const StackFrame = @import("env.zig").StackFrame;
const Val = @import("val.zig").Val;
const ListVal = @import("val.zig").ListVal;

pub const VmOptions = struct {
    comptime stack_size: usize = 4096,
    allocator: std.mem.Allocator,
};

pub const Vm = struct {
    options: VmOptions,
    env: Env,

    pub fn init(options: VmOptions) !Vm {
        return Vm{
            .options = options,
            .env = try Env.init(options.allocator, options.stack_size),
        };
    }

    pub fn allocator(self: *Vm) std.mem.Allocator {
        return self.options.allocator;
    }

    pub fn newSymbol(self: *Vm, str: []const u8) !Val {
        return Val{
            .symbol = try self.env.objects.symbols.strToSymbol(self.options.allocator, str),
        };
    }

    pub fn evalStr(self: *Vm, source: []const u8) !Val {
        var ast_builder = AstBuilder.init(self, source);
        var compiler = Compiler.init(self);
        defer compiler.deinit();
        var ret = Val{ .void = {} };
        while (try ast_builder.next()) |ast| {
            try compiler.compile(ast);
            self.env.resetStacks();
            const stack_frame = StackFrame{
                .instructions = compiler.currentExpr(),
                .stack_start = 0,
            };
            try self.env.stack_frames.append(self.allocator(), stack_frame);
            ret = try self.run();
        }
        return ret;
    }

    pub fn deinit(self: *Vm) void {
        self.env.deinit(self.options.allocator);
    }

    fn run(self: *Vm) !Val {
        var return_value = Val{ .void = {} };
        while (self.env.nextInstruction()) |instruction| {
            switch (instruction) {
                .push => |val| try self.executePush(val),
                .eval => |n| try self.executeEval(n),
                .ret => return_value = try self.executeRet(),
            }
        }
        return return_value;
    }

    fn executePush(self: *Vm, val: Val) !void {
        try self.env.pushVal(val);
    }

    fn executeEval(_: *Vm, _: usize) !void {
        unreachable("TODO: not implemented");
    }

    fn executeRet(self: *Vm) !Val {
        const ret = try self.env.popStackFrame();
        try self.executePush(ret);
        return ret;
    }
};

test "can make vm" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
}

test "eval constant returns constant" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("12");
    try std.testing.expectEqual(Val{ .int = 12 }, actual);
}

test "eval can return symbol" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("+");
    try std.testing.expectEqual(vm.newSymbol("+"), actual);
}

test "eval multiple constants returns last constant" {
    var vm = try Vm.init(VmOptions{ .allocator = std.testing.allocator });
    defer vm.deinit();
    const actual = try vm.evalStr("12 true false 4.5");
    try std.testing.expectEqual(Val{ .float = 4.5 }, actual);
}
