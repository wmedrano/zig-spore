pub const ValTag = enum {
    void,
    bool,
    int,
    float,
};

pub const Val = union(ValTag) {
    void,
    bool: bool,
    int: i64,
    float: f64,
};
