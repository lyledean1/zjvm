const std = @import("std");
const RawClassFile = @import("reader.zig").RawClassFile;
const Klass = @import("../runtime/klass.zig").Klass;
const Method = @import("../runtime/method.zig").Method;
const Field = @import("../runtime/field.zig").Field;
const CpAttr = @import("../class/constant_pool.zig").CpAttr;
const StackValue = @import("../runtime/stack.zig").StackValue;
const ConstantPoolInfo = @import("./constant_pool.zig").ConstantPoolInfo;

pub fn buildKlass(allocator: std.mem.Allocator, raw_class: *RawClassFile) !Klass {
    const class_name = try raw_class.getClassNameFromIndex(raw_class.this_class);
    const owned_name = try allocator.dupe(u8, class_name);

    const methods = try buildMethods(allocator, raw_class);

    const fields_result = try buildFields(allocator, raw_class);

    var method_lookup = std.StringHashMap(usize).init(allocator);
    var field_lookup = std.StringHashMap(usize).init(allocator);
    const s_val_lookup = std.StringHashMap(StackValue).init(allocator);

    for (methods, 0..) |method, i| {
        try method_lookup.put(method.name_desc, i);
    }

    for (fields_result.instance_fields, 0..) |field, i| {
        const key = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ field.name, field.desc });
        try field_lookup.put(key, i);
    }

    for (fields_result.static_fields, 0..) |field, i| {
        const key = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ field.name, field.desc });
        try field_lookup.put(key, i);
    }

    // Deep clone the constant pool to avoid use-after-free
    var owned_constant_pool = try std.ArrayList(ConstantPoolInfo).initCapacity(allocator, raw_class.constant_pool.capacity);
    for (raw_class.constant_pool.items) |entry| {
        const owned_entry = try deepCloneConstantPoolEntry(allocator, entry);
        try owned_constant_pool.append(allocator, owned_entry);
    }

    return Klass{
        .id = 0,
        .initialised = false,
        .name = owned_name,
        .flag = raw_class.access_flags,
        .constant_pool = owned_constant_pool,
        .methods = methods,
        .i_fields = fields_result.instance_fields,
        .s_fields = fields_result.static_fields,
        .s_field_vals = s_val_lookup,
        .m_name_desc_lookup = method_lookup,
        .f_name_desc_lookup = field_lookup,
    };
}

fn buildMethods(allocator: std.mem.Allocator, raw_class: *RawClassFile) ![]Method {
    var methods = try allocator.alloc(Method, raw_class.methods.items.len);

    for (raw_class.methods.items, 0..) |raw_method, i| {
        const method_name = try raw_class.getUtf8FromConstantPool(raw_method.name_index);
        const method_desc = try raw_class.getUtf8FromConstantPool(raw_method.descriptor_index);

        var bytecode: []u8 = &[_]u8{};
        var max_locals: u16 = 0;
        var max_stack: u16 = 0;
        for (raw_method.attributes.items) |attr| {
            if (attr.info == .Code) {
                bytecode = attr.info.Code.code;
                max_locals = attr.info.Code.max_locals;
                max_stack = attr.info.Code.max_stack;
                break;
            }
        }

        methods[i] = Method{
            .klass_name = try allocator.dupe(u8, raw_class.getClassNameFromIndex(raw_class.this_class) catch ""),
            .flags = raw_method.access_flags,
            .name = try allocator.dupe(u8, method_name),
            .name_desc = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ method_name, method_desc }),
            .name_idx = raw_method.name_index,
            .code = try allocator.dupe(u8, bytecode),
            .max_locals = max_locals,
            .max_stack = max_stack,
            .attrs = &[_]CpAttr{}, // Convert attributes if needed
        };
    }

    return methods;
}

const FieldsResult = struct {
    instance_fields: []Field,
    static_fields: []Field,
};

fn buildFields(allocator: std.mem.Allocator, raw_class: *RawClassFile) !FieldsResult {
    var instance_fields = try std.ArrayList(Field).initCapacity(allocator, 0);
    var static_fields = try std.ArrayList(Field).initCapacity(allocator, 0);
    defer instance_fields.deinit(allocator);
    defer static_fields.deinit(allocator);

    var instance_offset: u16 = 0;
    var static_offset: u16 = 0;

    for (raw_class.fields.items) |raw_field| {
        var constant_value_index: ?u16 = null;
        const field_name = try raw_class.getUtf8FromConstantPool(raw_field.name_index);
        const field_desc = try raw_class.getUtf8FromConstantPool(raw_field.descriptor_index);
        const is_static = (raw_field.access_flags & 0x0008) != 0; // ACC_STATIC

        for (raw_field.attributes.items) |attr| {
            if (attr.info == .ConstantValue) {
                constant_value_index = attr.info.ConstantValue.constantvalue_index;
                break;
            }
        }

        const field = Field{
            .offset = if (is_static) static_offset else instance_offset,
            .klass_name = try allocator.dupe(u8, raw_class.getClassNameFromIndex(raw_class.this_class) catch ""),
            .flags = raw_field.access_flags,
            .name_idx = raw_field.name_index,
            .desc_idx = raw_field.descriptor_index,
            .name = try allocator.dupe(u8, field_name),
            .desc = try allocator.dupe(u8, field_desc),
            .attrs = &[_]CpAttr{},
            .constant_value_idx = constant_value_index orelse 0,
        };

        if (is_static) {
            try static_fields.append(allocator, field);
            static_offset += getFieldSize(field_desc);
        } else {
            try instance_fields.append(allocator, field);
            instance_offset += getFieldSize(field_desc);
        }
    }

    return FieldsResult{
        .instance_fields = try instance_fields.toOwnedSlice(allocator),
        .static_fields = try static_fields.toOwnedSlice(allocator),
    };
}

fn getFieldSize(descriptor: []const u8) u16 {
    return switch (descriptor[0]) {
        'B', 'C', 'Z' => 1,
        'S' => 2, //
        'I', 'F' => 4,
        'J', 'D' => 8,
        'L', '[' => 8,
        else => 4,
    };
}

fn deepCloneConstantPoolEntry(allocator: std.mem.Allocator, entry: ConstantPoolInfo) !ConstantPoolInfo {
    return switch (entry) {
        .Utf8 => |bytes| .{ .Utf8 = try allocator.dupe(u8, bytes) },
        .Integer => |value| .{ .Integer = value },
        .Float => |value| .{ .Float = value },
        .Long => |value| .{ .Long = value },
        .Double => |value| .{ .Double = value },
        .Class => |name_index| .{ .Class = name_index },
        .String => |string_index| .{ .String = string_index },
        .Fieldref => |fieldref| .{ .Fieldref = fieldref },
        .Methodref => |methodref| .{ .Methodref = methodref },
        .InterfaceMethodref => |interface_methodref| .{ .InterfaceMethodref = interface_methodref },
        .NameAndType => |name_and_type| .{ .NameAndType = name_and_type },
        else => entry, // For any other types, just copy as-is
    };
}
