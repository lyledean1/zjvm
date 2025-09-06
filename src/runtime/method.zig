const CpAttr = @import("../class/constant_pool.zig").CpAttr;

pub const Method = struct {
    klass_name: []u8,
    flags: u16,
    name: []u8,
    name_desc: []u8,
    name_idx: u16,
    code: []u8,
    max_locals: u16,
    max_stack: u16,
    attrs: []CpAttr,
};
