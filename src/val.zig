const Symbol = @import("symbol.zig").Symbol;
const ObjectId = @import("object_manager.zig").ObjectId;

pub const ListVal = struct {
    list: []Val,
};

pub const ValTag = enum {
    void,
    bool,
    int,
    float,
    symbol,
    list,
};

pub const Val = union(ValTag) {
    void,
    bool: bool,
    int: i64,
    float: f64,
    symbol: Symbol,
    list: ObjectId(ListVal),
};
