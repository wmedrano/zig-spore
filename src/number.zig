const Val = @import("Val.zig");

pub const Number = union(enum) {
    int: i64,
    float: f64,

    pub fn toVal(self: Number) Val {
        const val = Val.fromZig(void, self) catch unreachable;
        return val;
    }
};
