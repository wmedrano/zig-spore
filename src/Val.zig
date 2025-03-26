const std = @import("std");

const Instruction = @import("instruction.zig").Instruction;
const ObjectManager = @import("ObjectManager.zig");
const Vm = @import("Vm.zig");
const Symbol = @import("Symbol.zig");

const Val = @This();

repr: ValRepr,

pub const FunctionError = error{
    BadArg,
    NotImplemented,
    ObjectNotFound,
    StackOverflow,
    WrongArity,
    WrongType,
} || @import("AstBuilder.zig").Error || std.mem.Allocator.Error;

pub const ValTag = enum {
    void,
    bool,
    int,
    float,
    string,
    symbol,
    list,
    function,
    bytecode_function,
};

const ValRepr = union(ValTag) {
    void,
    bool: bool,
    int: i64,
    float: f64,
    string: ObjectManager.Id(String),
    symbol: InternedSymbol,
    list: ObjectManager.Id(List),
    function: *const FunctionVal,
    bytecode_function: ObjectManager.Id(ByteCodeFunction),
};

/// Initialize a new `Val` to the default `void` value.
pub fn init() Val {
    return .{ .repr = .{ .void = {} } };
}

/// Convert from a Zig value to a Spore `Val`.
///
/// Supported Types:
/// - `Val` - Returns `val` as is.
/// - `void` - Converts to a `Val.void`.
/// - `bool` - Converts to a `Val.bool`.
/// - `i64` - Converts to a `Val.int`.
/// - `f64` - Converts to a `Val.float`.
/// - `[]const u8` - Creates a new `Val.string` by copying the slice
///     contents.
/// - `Symbol` - Converts to a `Val.symbol`.
/// - `InternedSymbol` - Converts to a `Val.symbol`.
/// - `[]const Val` - Converts to a `Val.list`.
pub fn fromZig(comptime T: type, vm: *Vm, val: T) !Val {
    if (T == Val) return val;
    switch (T) {
        void => return init(),
        bool => return .{ .repr = .{ .bool = val } },
        i64 => return .{ .repr = .{ .int = val } },
        f64 => return .{ .repr = .{ .float = val } },
        []const u8 => {
            const owned_string = try vm.allocator().dupe(u8, val);
            const id = try vm.objects.put(String, vm.allocator(), .{ .string = owned_string });
            return .{ .repr = .{ .string = id } };
        },
        Symbol => {
            const interned_symbol = try InternedSymbol.fromSymbol(vm, val);
            return interned_symbol.toVal();
        },
        InternedSymbol => return val.toVal(),
        []const Val => {
            const owned_list = try vm.allocator().dupe(Val, val);
            return fromOwnedList(vm, owned_list);
        },
        else => @compileError("fromZig not supported for type " ++ @typeName(T)),
    }
}

pub const ToZigError = error{
    WrongType,
    ObjectNotFound,
};

/// Convert from a Spore `Val` to a Zig value.
///
/// Supported Types `T`:
/// - `void`
/// - `bool`
/// - `i64`
/// - `f64`
/// - `[]const u8` (returns a slice pointing to the Val's internal string)
/// - `Symbol`
/// - `InternedSymbol`
/// - `[]const Val` (returns a slice pointing to the Val's internal list)
///
/// Note: For slice types (`[]const u8`, `[]const Val`), the returned slice's
/// lifetime is tied to the underlying object in the Vm's ObjectManager.
/// The caller must ensure the Vm and its objects outlive the use of the slice.
pub fn toZig(self: Val, comptime T: type, vm: *const Vm) ToZigError!T {
    // Disallow Val -> Val conversion via this function
    if (T == Val) return self;

    switch (self.repr) {
        .void => {
            if (T == void) return;
            return ToZigError.WrongType;
        },
        .bool => |v| {
            if (T == bool) return v;
            return ToZigError.WrongType;
        },
        .int => |v| {
            if (T == i64) return v;
            // TODO: Add explicit conversions for other int types if needed, e.g.:
            // if (T == i32) return @intCast(i32, v) catch return ToZigError.WrongType;
            return ToZigError.WrongType;
        },
        .float => |v| {
            if (T == f64) return v;
            // TODO: Add explicit conversions for f32 if needed.
            return ToZigError.WrongType;
        },
        .string => {
            if (T == []const u8) {
                if (self.asString(vm)) |s| {
                    return s;
                } else {
                    // asString returns null if not a string OR if object not found.
                    // We know it's a string tag, so null means ObjectNotFound.
                    return ToZigError.ObjectNotFound;
                }
            }
            return ToZigError.WrongType;
        },
        .symbol => |interned_symbol| {
            if (T == InternedSymbol) return interned_symbol;
            if (T == Symbol) {
                // Convert InternedSymbol back to Symbol via the interner.
                const maybe_symbol = vm.objects.symbols.internedSymbolToSymbol(interned_symbol);
                if (maybe_symbol) |symbol| {
                    return symbol;
                } else {
                    // If internedSymbolToSymbol returns null, the ID was invalid.
                    // This indicates an internal inconsistency or a stale ID.
                    return ToZigError.ObjectNotFound; // Treat as object not found.
                }
            }
            return ToZigError.WrongType;
        },
        .list => {
            if (T == []const Val) {
                if (self.asList(vm.*)) |l| {
                    return l;
                }
                // asList returns null if not a list OR if object not found.
                // We know it's a list tag, so null means ObjectNotFound.
                return ToZigError.ObjectNotFound;
            }
            // TODO: Handle conversion to owned list ([]Val) if needed (requires allocator).
            return ToZigError.WrongType;
        },
        // Types not generally convertible back to simple Zig types.
        .function, .bytecode_function => return ToZigError.WrongType,
    }
}

pub fn fromOwnedList(vm: *Vm, owned_list: []Val) !Val {
    const id = try vm.objects.put(List, vm.allocator(), .{ .list = owned_list });
    return .{ .repr = .{ .list = id } };
}

pub fn fromSymbolStr(vm: *Vm, symbol_str: []const u8) !Val {
    const symbol = try Symbol.fromStr(symbol_str);
    return Val.fromZig(Symbol, vm, symbol);
}

pub fn asInternedSymbol(self: Val) ?InternedSymbol {
    switch (self.repr) {
        .symbol => |symbol| return symbol,
        else => return null,
    }
}

/// Returns true if `Val` is an int.
pub fn isInt(self: Val) bool {
    switch (self.repr) {
        .int => return true,
        else => return false,
    }
}

fn asString(self: Val, vm: *const Vm) ?[]const u8 {
    switch (self.repr) {
        .string => |id| {
            const string = if (vm.objects.get(String, id)) |string| string else return null;
            return string.string;
        },
        else => return null,
    }
}

/// Get the underlying value as a `Symbol`.
pub fn asSymbol(self: Val, vm: Vm) !?Symbol {
    const symbol = if (self.asInternedSymbol()) |s| s else return null;
    return vm.objects.symbols.internedSymbolToSymbol(symbol);
}

fn asList(self: Val, vm: Vm) ?[]const Val {
    switch (self.repr) {
        .list => |id| {
            const list = if (vm.objects.get(List, id)) |list| list else return null;
            return list.list;
        },
        else => return null,
    }
}

/// Get a struct that can format `Val`.
pub fn formatted(self: Val, vm: *const Vm) FormattedVal {
    return FormattedVal{ .val = self, .vm = vm };
}

const FormattedVal = struct {
    val: Val,
    vm: *const Vm,

    pub fn format(
        self: FormattedVal,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self.val.repr) {
            .void => try writer.print("<void>", .{}),
            .bool => |x| try writer.print("{any}", .{x}),
            .int => |x| try writer.print("{any}", .{x}),
            .float => |x| try writer.print("{any}", .{x}),
            .string => {
                const string = try self.val.toZig([]const u8, self.vm);
                try writer.print("\"{s}\"", .{string});
            },
            .symbol => {
                const symbol = self.val.asSymbol(self.vm.*);
                try writer.print("{any}", .{symbol});
            },
            .list => {
                const list = self.val.asList(self.vm.*).?;
                try writer.print("(", .{});
                for (list, 0..list.len) |v, idx| {
                    if (idx == 0) {
                        try writer.print("{any}", .{v.formatted(self.vm)});
                    } else {
                        try writer.print(" {any}", .{v.formatted(self.vm)});
                    }
                }
                try writer.print(")", .{});
            },
            .function => |f| {
                try writer.print("(native-function {any})", .{f.name});
            },
            .bytecode_function => |id| {
                const f = self.vm.objects.get(ByteCodeFunction, id).?;
                try writer.print("(function {any})", .{f.name});
            },
        }
    }
};

pub const InternedSymbol = packed struct {
    quotes: u2,
    id: u30,

    pub fn fromSymbolStr(vm: *Vm, symbol_str: []const u8) !InternedSymbol {
        return InternedSymbol.fromSymbol(vm, try Symbol.fromStr(symbol_str));
    }

    pub fn fromSymbol(vm: *Vm, symbol: Symbol) !InternedSymbol {
        return try vm.objects.symbols.strToSymbol(
            vm.allocator(),
            symbol,
        );
    }

    pub fn eql(self: InternedSymbol, other: InternedSymbol) bool {
        return self.quotes == other.quotes and self.id == other.id;
    }

    pub fn toVal(self: InternedSymbol) Val {
        return .{ .repr = .{ .symbol = self } };
    }

    pub fn toSymbol(self: InternedSymbol, vm: Vm) ?Symbol {
        return vm.objects.symbols.internedSymbolToSymbol(self);
    }

    pub fn quoted(self: InternedSymbol) InternedSymbol {
        if (self.quotes == std.math.maxInt(u2)) return self;
        return InternedSymbol{
            .quotes = self.quotes + 1,
            .id = self.id,
        };
    }

    pub fn unquoted(self: InternedSymbol) InternedSymbol {
        if (self.quotes == 0) return self;
        return InternedSymbol{
            .quotes = self.quotes - 1,
            .id = self.id,
        };
    }
};

pub const String = struct {
    string: []const u8,

    pub fn garbageCollect(self: *String, allocator: std.mem.Allocator) void {
        if (self.string.len > 0) {
            allocator.free(self.string);
        }
        self.string = "";
    }

    pub fn markChildren(_: String, _: *ObjectManager) void {}
};

pub const List = struct {
    list: []Val,

    pub fn garbageCollect(self: *List, allocator: std.mem.Allocator) void {
        if (self.list.len > 0) {
            allocator.free(self.list);
            self.list = &[0]Val{};
        }
    }

    pub fn markChildren(self: List, obj: *ObjectManager) void {
        for (self.list) |v| {
            obj.markReachable(v);
        }
    }
};

pub const FunctionVal = struct {
    name: []const u8,
    function: *const fn (*Vm) FunctionError!Val,
};

pub const ByteCodeFunction = struct {
    name: []const u8,
    instructions: []const Instruction,

    pub fn garbageCollect(self: *ByteCodeFunction, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.instructions);
    }

    pub fn markChildren(self: ByteCodeFunction, obj: *ObjectManager) void {
        for (self.instructions) |instruction| {
            switch (instruction) {
                .push => |v| obj.markReachable(v),
                .eval => {},
                .deref => {},
                .ret => {},
            }
        }
    }
};

test "val is small" {
    try std.testing.expectEqual(2 * @sizeOf(u64), @sizeOf(Val));
}
