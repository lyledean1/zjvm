const CpAttr = @import("../class/constant_pool.zig").CpAttr;

pub const Field = struct {
    offset: u16,
    klass_name: []u8,
    flags: u16,
    name_idx: u16,
    desc_idx: u16,
    name: []u8,
    desc: []u8,
    attrs: []CpAttr,
    constant_value_idx: u16,
};
