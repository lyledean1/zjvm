const std = @import("std");
const NameTypeField = enum { name, descriptor };

pub const ConstantTag = enum(u8) {
    Utf8 = 1,
    Integer = 3,
    Float = 4,
    Long = 5,
    Double = 6,
    Class = 7,
    String = 8,
    Fieldref = 9,
    Methodref = 10,
    InterfaceMethodref = 11,
    NameAndType = 12,
    _,
};

pub const ConstantPoolInfo = union(ConstantTag) {
    Utf8: []const u8,
    Integer: i32,
    Float: f32,
    Long: i64,
    Double: f64,
    Class: u16,
    String: u16,
    Fieldref: struct { class_index: u16, name_and_type_index: u16 },
    Methodref: struct { class_index: u16, name_and_type_index: u16 },
    InterfaceMethodref: struct { class_index: u16, name_and_type_index: u16 },
    NameAndType: struct { name_index: u16, descriptor_index: u16 },
};

pub const CpRef = struct {
    clz_idx: u16,
    nt_idx: u16,
};

pub const NameAndType = struct {
    name_idx: u16,
    type_idx: u16,
};

pub const CpAttr = struct {
    name_idx: u16,
};

fn getRefNameOrType(items: []ConstantPoolInfo, entry: ConstantPoolInfo, field: NameTypeField) ![]const u8 {
    const name_and_type_index = switch (entry) {
        .Methodref => |methodref| blk: {
            break :blk methodref.name_and_type_index;
        },
        .InterfaceMethodref => |methodref| blk: {
            break :blk methodref.name_and_type_index;
        },
        .Fieldref => |fieldref| blk: {
            break :blk fieldref.name_and_type_index;
        },
        else => return error.NotReference,
    };

    if (name_and_type_index == 0 or name_and_type_index > items.len) {
        return error.InvalidIndex;
    }

    const name_and_type_entry = items[name_and_type_index - 1];
    return switch (name_and_type_entry) {
        .NameAndType => |name_and_type| {
            return switch (field) {
                .name => getUtf8FromConstantPool(items, name_and_type.name_index),
                .descriptor => getUtf8FromConstantPool(items, name_and_type.descriptor_index),
            };
        },
        else => error.NotNameAndType,
    };
}

pub fn getMethodDescriptor(items: []ConstantPoolInfo, entry: ConstantPoolInfo) ![]const u8 {
    return switch (entry) {
        .Methodref => getRefNameOrType(items, entry, .descriptor),
        .InterfaceMethodref => getRefNameOrType(items, entry, .descriptor),
        else => error.NotMethodRef,
    };
}

pub fn getFieldName(items: []ConstantPoolInfo, entry: ConstantPoolInfo) ![]const u8 {
    return switch (entry) {
        .Fieldref => getRefNameOrType(items, entry, .name),
        else => error.NotFieldRef,
    };
}

pub fn getFieldType(items: []ConstantPoolInfo, entry: ConstantPoolInfo) ![]const u8 {
    return switch (entry) {
        .Fieldref => getRefNameOrType(items, entry, .descriptor),
        else => error.NotFieldRef,
    };
}

pub fn getMethodName(items: []ConstantPoolInfo, entry: ConstantPoolInfo) ![]const u8 {
    return switch (entry) {
        .Methodref => getRefNameOrType(items, entry, .name),
        .InterfaceMethodref => getRefNameOrType(items, entry, .name),
        else => error.NotMethodRef,
    };
}

pub fn getNameAndTypeFromIndex(items: []ConstantPoolInfo, index: u16) !struct { name: []const u8, descriptor: []const u8 } {
    if (index == 0 or index > items.len) {
        return error.NotImplemented;
    }

    const entry = items[index - 1];
    return switch (entry) {
        .NameAndType => |name_and_type| .{
            .name = getUtf8FromConstantPool(items, name_and_type.name_index) catch return error.NotImplemented,
            .descriptor = getUtf8FromConstantPool(items, name_and_type.descriptor_index) catch return error.NotImplemented,
        },
        else => error.NotImplemented,
    };
}
pub fn getClassName(items: []ConstantPoolInfo, entry: ConstantPoolInfo) ![]const u8 {
    return switch (entry) {
        .Methodref => |methodref| {
            return getClassNameFromIndex(items, methodref.class_index);
        },
        .InterfaceMethodref => |methodref| {
            return getClassNameFromIndex(items, methodref.class_index);
        },
        .Fieldref => |fieldref| {
            return getClassNameFromIndex(items, fieldref.class_index);
        },
        .Class => |clz| {
            return getClassNameFromIndex(items, clz);
        },
        else => {
            std.debug.print("Not Method Ref {any}\n", .{entry});
            return error.NotMethodRef;
        },
    };
}

pub fn getUtf8FromConstantPool(items: []ConstantPoolInfo, index: u16) ![]const u8 {
    if (index == 0 or index > items.len) {
        return error.NotImplemented;
    }

    const entry = items[index - 1];
    return switch (entry) {
        .Utf8 => |bytes| bytes,
        else => error.NotImplemented,
    };
}

pub fn getClassNameFromIndex(items: []ConstantPoolInfo, index: u16) ![]const u8 {
    if (index == 0 or index > items.len) {
        return error.NotImplemented;
    }

    const entry = items[index - 1];
    return switch (entry) {
        .Class => |name_index| getUtf8FromConstantPool(items, name_index),
        .Utf8 => |name| name,
        else => error.NotImplemented,
    };
}

pub fn isMethod(cname: []const u8, mname: []const u8, items: []ConstantPoolInfo, entry: ConstantPoolInfo) bool {
    return switch (entry) {
        .Fieldref => |fieldref| {
            if (getClassNameFromIndex(items, fieldref.class_index)) |class_name| {
                if (std.mem.eql(u8, class_name, cname)) {
                    if (getNameAndTypeFromIndex(items, fieldref.name_and_type_index)) |name_type| {
                        return std.mem.eql(u8, name_type.name, mname);
                    } else |_| {}
                }
            } else |_| {}
            return false;
        },
        .Methodref => |methodref| {
            if (getClassNameFromIndex(items, methodref.class_index)) |class_name| {
                if (std.mem.eql(u8, class_name, cname)) {
                    if (getNameAndTypeFromIndex(items, methodref.name_and_type_index)) |name_type| {
                        return std.mem.eql(u8, name_type.name, mname);
                    } else |_| {}
                }
            } else |_| {}
            return false;
        },
        else => false,
    };
}

pub fn countMethodParameters(descriptor: []const u8) u8 {
    var count: u8 = 0;
    var i: usize = 1;

    while (i < descriptor.len and descriptor[i] != ')') {
        switch (descriptor[i]) {
            'B', 'C', 'D', 'F', 'I', 'J', 'S', 'Z' => {
                count += 1;
                i += 1;
            },
            'L' => {
                count += 1;
                while (i < descriptor.len and descriptor[i] != ';') {
                    i += 1;
                }
                i += 1;
            },
            '[' => {
                count += 1;
                i += 1;
                while (i < descriptor.len and descriptor[i] == '[') {
                    i += 1;
                }
                if (i < descriptor.len) {
                    if (descriptor[i] == 'L') {
                        while (i < descriptor.len and descriptor[i] != ';') {
                            i += 1;
                        }
                        i += 1;
                    } else {
                        i += 1;
                    }
                }
            },
            else => {
                i += 1;
            },
        }
    }
    return count;
}

// print helpers
fn parseConstantPool(items: []ConstantPoolInfo, entry: ConstantPoolInfo) void {
    switch (entry) {
        .Utf8 => |bytes| {
            std.debug.print("Utf8 = \"{s}\"\n", .{bytes});
        },
        .Integer => |value| {
            std.debug.print("Integer = {d}\n", .{value});
        },
        .Float => |value| {
            std.debug.print("Float = {d}\n", .{value});
        },
        .Long => |value| {
            std.debug.print("Long = {d}\n", .{value});
        },
        .Double => |value| {
            std.debug.print("Double = {d}\n", .{value});
        },
        .String => |string_index| {
            std.debug.print(" String = #{d}", .{string_index});
            if (getUtf8FromConstantPool(items, string_index)) |string| {
                std.debug.print(" (\"{s}\")", .{string});
            } else |_| {}
        },
        .Fieldref => |fieldref| {
            std.debug.print(" Fieldref = #{d}.#{d}", .{ fieldref.class_index, fieldref.name_and_type_index });
            printFieldrefDetails(items, fieldref.class_index, fieldref.name_and_type_index);
        },
        .Methodref => |methodref| {
            std.debug.print(" Methodref = #{d}.#{d}", .{ methodref.class_index, methodref.name_and_type_index });
            printFieldrefDetails(items, methodref.class_index, methodref.name_and_type_index);
        },
        else => {
            //todo
        },
    }
}

fn printFieldrefDetails(items: []ConstantPoolInfo, class_index: u16, name_and_type_index: u16) void {
    if (getClassNameFromIndex(items, class_index)) |class_name| {
        if (getNameAndTypeFromIndex(items, name_and_type_index)) |name_and_type| {
            std.debug.print(" ({s}.{s}:{s})", .{ class_name, name_and_type.name, name_and_type.descriptor });
        } else |_| {
            std.debug.print(" ({s}.<invalid>)", .{class_name});
        }
    } else |_| {}
}
