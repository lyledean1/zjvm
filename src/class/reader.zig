const std = @import("std");
const bc = @import("./bytecode.zig");
const ConstantPoolInfo = @import("./constant_pool.zig").ConstantPoolInfo;
const ConstantTag = @import("./constant_pool.zig").ConstantTag;

pub fn decodeBytecode(bytecode: []const u8) !void {
    var i: usize = 0;
    while (i < bytecode.len) {
        const opcode_byte = bytecode[i];
        const opcode = std.meta.intToEnum(bc.Opcode, opcode_byte) catch bc.Opcode.nop;
        const info = bc.getInstructionInfo(opcode);

        std.debug.print("\t\t   {X:0>2}: {s}", .{ opcode_byte, info.name });

        if (info.operand_count > 0 and i + info.operand_count < bytecode.len) {
            std.debug.print(" ", .{});
            var j: u8 = 1;
            while (j <= info.operand_count) : (j += 1) {
                std.debug.print("{X:0>2}", .{bytecode[i + j]});
                if (j < info.operand_count) std.debug.print(" ", .{});
            }

            if (info.operand_count == 2) {
                const index = (@as(u16, bytecode[i + 1]) << 8) | bytecode[i + 2];
                std.debug.print(" (#{d})", .{index});
            } else if (info.operand_count == 1 and std.mem.eql(u8, info.name, "ldc")) {
                std.debug.print(" (#{d})", .{bytecode[i + 1]});
            }
        }

        std.debug.print(" // {s}\n", .{info.description});

        i += 1 + info.operand_count;
    }
}

pub const ClassFileError = error{ InvalidMagic, InvalidTag, InvalidUtf8, EndOfStream, InvalidClassFile, NotImplemented };

const AttributeInfo = struct {
    attribute_name_index: u16,
    attribute_length: u32,
    info: AttributeData,
};

pub const AttributeData = union(enum) {
    Code: CodeAttribute,
    LineNumberTable: LineNumberTableAttribute,
    SourceFile: SourceFileAttribute,
    ConstantValue: ConstantValueAttribute,
    Unknown: []u8, // For attributes we don't handle yet
};

pub const CodeAttribute = struct {
    max_stack: u16,
    max_locals: u16,
    code_length: u32,
    code: []u8,
    exception_table_length: u16,
    exception_table: []ExceptionTableEntry,
    attributes_count: u16,
    attributes: std.ArrayList(AttributeInfo),
};

const ExceptionTableEntry = struct {
    start_pc: u16,
    end_pc: u16,
    handler_pc: u16,
    catch_type: u16,
};

const LineNumberTableAttribute = struct {
    line_number_table_length: u16,
    line_number_table: []LineNumberEntry,
};

const LineNumberEntry = struct {
    start_pc: u16,
    line_number: u16,
};

const SourceFileAttribute = struct {
    sourcefile_index: u16,
};

pub const ConstantValueAttribute = struct {
    constantvalue_index: u16,
};

const FieldInfo = struct {
    access_flags: u16,
    name_index: u16,
    descriptor_index: u16,
    attributes_count: u16,
    attributes: std.ArrayList(AttributeInfo),
};

const MethodInfo = struct {
    access_flags: u16,
    name_index: u16,
    descriptor_index: u16,
    attributes_count: u16,
    attributes: std.ArrayList(AttributeInfo),
};

pub const RawClassFile = struct {
    minor_version: u16,
    major_version: u16,
    constant_pool_count: u16,
    constant_pool: std.ArrayList(ConstantPoolInfo),
    access_flags: u16,
    this_class: u16,
    super_class: u16,
    interfaces_count: u16,
    interfaces: std.ArrayList(u16),
    fields_count: u16,
    fields: std.ArrayList(FieldInfo),
    method_count: u16,
    methods: std.ArrayList(MethodInfo), // Change this from ArrayList(u16)
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !RawClassFile {
        return RawClassFile{
            .minor_version = 0,
            .major_version = 0,
            .constant_pool_count = 0,
            .constant_pool = try std.ArrayList(ConstantPoolInfo).initCapacity(allocator, 0),
            .access_flags = 0,
            .this_class = 0,
            .super_class = 0,
            .interfaces_count = 0,
            .interfaces = try std.ArrayList(u16).initCapacity(allocator, 0),
            .fields_count = 0,
            .fields = try std.ArrayList(FieldInfo).initCapacity(allocator, 0),
            .method_count = 0,
            .methods = try std.ArrayList(MethodInfo).initCapacity(allocator, 0),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RawClassFile) void {
        for (self.methods.items) |*method| {
            self.deinitAttributes(&method.attributes);
            method.attributes.deinit(self.allocator);
        }
        self.methods.deinit(self.allocator);
        for (self.fields.items) |*method| {
            self.deinitAttributes(&method.attributes);
            method.attributes.deinit(self.allocator);
        }
        self.fields.deinit(self.allocator);
        for (self.constant_pool.items) |info| {
            if (info == .Utf8) {
                self.allocator.free(info.Utf8);
            }
        }
        self.constant_pool.deinit(self.allocator);
        self.interfaces.deinit(self.allocator);
    }

    fn deinitAttributes(self: *RawClassFile, attributes: *std.ArrayList(AttributeInfo)) void {
        for (attributes.items) |*attr| {
            switch (attr.info) {
                .Code => |*code| {
                    self.allocator.free(code.code);
                    self.allocator.free(code.exception_table);
                    // Recursively clean up nested attributes in Code attribute
                    self.deinitAttributes(&code.attributes);
                    code.attributes.deinit(self.allocator);
                },
                .LineNumberTable => |*lnt| {
                    self.allocator.free(lnt.line_number_table);
                },
                .Unknown => |data| {
                    self.allocator.free(data);
                },
                else => {},
            }
        }
    }

    pub fn parse(self: *RawClassFile, reader: anytype) !void {
        const magic = try reader.readInt(u32, .big);
        if (magic != 0xCAFEBABE) {
            return ClassFileError.InvalidMagic;
        }
        self.minor_version = try reader.readInt(u16, .big);
        self.major_version = try reader.readInt(u16, .big);
        self.constant_pool_count = try reader.readInt(u16, .big);
        self.constant_pool = try self.getConstantPool(reader, self.constant_pool_count);
        self.access_flags = try reader.readInt(u16, .big);
        self.this_class = try reader.readInt(u16, .big);
        self.super_class = try reader.readInt(u16, .big);
        self.interfaces_count = try reader.readInt(u16, .big);
        self.interfaces = try self.getInterfacesCount(self.interfaces_count);
        self.fields_count = try reader.readInt(u16, .big);
        self.fields = try self.parseFields(reader, self.fields_count);
        self.method_count = try reader.readInt(u16, .big);
        self.methods = try self.parseMethods(reader, self.method_count);
    }

    pub fn print(self: *RawClassFile) void {
        std.debug.print("Version: {d}.{d}\n", .{ self.major_version, self.minor_version });
        std.debug.print("Access flags: 0x{X:0>4}\n", .{self.access_flags});
        std.debug.print("This class: {d}\n", .{self.this_class});
        std.debug.print("Super class: {d}\n", .{self.super_class});
        std.debug.print("Interfaces count: {d}\n", .{self.interfaces.items.len});
        std.debug.print("Constant pool count: {d}\n", .{self.constant_pool_count});
        std.debug.print("Fields count: {d}\n", .{self.fields_count});
        std.debug.print("Method count: {d}\n", .{self.method_count});

        self.printConstantPool();
        self.printMethods();
        self.printFields();
    }

    fn getInterfacesCount(self: *RawClassFile, count: u16) !std.ArrayList(u16) {
        if (count > 0) {
            return ClassFileError.NotImplemented;
        }
        return try std.ArrayList(u16).initCapacity(self.allocator, 0);
    }

    fn getFieldsCount(self: *RawClassFile, count: u16) !std.ArrayList(u16) {
        if (count > 0) {
            return ClassFileError.NotImplemented;
        }
        return std.ArrayList(u16).init(self.allocator);
    }

    fn getConstantPool(self: *RawClassFile, reader: anytype, count: u16) !std.ArrayList(ConstantPoolInfo) {
        var constant_pool = try std.ArrayList(ConstantPoolInfo).initCapacity(self.allocator, 0);

        // The constant pool is 1-indexed, so we iterate from 1 to count-1
        // This gives us (count-1) actual entries
        var i: u16 = 1;
        while (i < count) : (i += 1) {
            const tag_byte = try reader.readInt(u8, .big);
            const tag = std.meta.intToEnum(ConstantTag, tag_byte) catch {
                return ClassFileError.InvalidTag;
            };

            const info = try self.parseConstantPoolInfo(reader, tag);
            try constant_pool.append(self.allocator, info);

            // Long and Double entries take up two slots in the constant pool
            if (tag == .Long or tag == .Double) {
                i += 1; // Skip the next index
            }
        }

        return constant_pool;
    }

    fn parseConstantPoolInfo(self: *RawClassFile, reader: anytype, tag: ConstantTag) !ConstantPoolInfo {
        return switch (tag) {
            .Utf8 => {
                const length = try reader.readInt(u16, .big);
                const bytes = try self.allocator.alloc(u8, length);
                _ = try reader.readAll(bytes);
                return ConstantPoolInfo{ .Utf8 = bytes };
            },
            .Integer => ConstantPoolInfo{ .Integer = try reader.readInt(i32, .big) },
            .Float => {
                const bits = try reader.readInt(u32, .big);
                return ConstantPoolInfo{ .Float = @as(f32, @bitCast(bits)) };
            },
            .Long => ConstantPoolInfo{ .Long = try reader.readInt(i64, .big) },
            .Double => {
                const bits = try reader.readInt(u64, .big);
                return ConstantPoolInfo{ .Double = @as(f64, @bitCast(bits)) };
            },
            .Class => ConstantPoolInfo{ .Class = try reader.readInt(u16, .big) },
            .String => ConstantPoolInfo{ .String = try reader.readInt(u16, .big) },
            .Fieldref => ConstantPoolInfo{
                .Fieldref = .{
                    .class_index = try reader.readInt(u16, .big),
                    .name_and_type_index = try reader.readInt(u16, .big),
                },
            },
            .Methodref => ConstantPoolInfo{
                .Methodref = .{
                    .class_index = try reader.readInt(u16, .big),
                    .name_and_type_index = try reader.readInt(u16, .big),
                },
            },
            .InterfaceMethodref => ConstantPoolInfo{
                .InterfaceMethodref = .{
                    .class_index = try reader.readInt(u16, .big),
                    .name_and_type_index = try reader.readInt(u16, .big),
                },
            },
            .NameAndType => ConstantPoolInfo{
                .NameAndType = .{
                    .name_index = try reader.readInt(u16, .big),
                    .descriptor_index = try reader.readInt(u16, .big),
                },
            },
            _ => ClassFileError.InvalidTag,
        };
    }

    fn parseMethods(self: *RawClassFile, reader: anytype, count: u16) (ClassFileError || std.mem.Allocator.Error || @TypeOf(reader).Error)!std.ArrayList(MethodInfo) {
        var methods = try std.ArrayList(MethodInfo).initCapacity(self.allocator, 0);

        var i: u16 = 0;
        while (i < count) : (i += 1) {
            const method = try self.parseMethodInfo(reader);
            try methods.append(self.allocator, method);
        }

        return methods;
    }

    fn parseFields(self: *RawClassFile, reader: anytype, count: u16) (ClassFileError || std.mem.Allocator.Error || @TypeOf(reader).Error)!std.ArrayList(FieldInfo) {
        var fields = try std.ArrayList(FieldInfo).initCapacity(self.allocator, 0);

        var i: u16 = 0;
        while (i < count) : (i += 1) {
            const field = try self.parseFieldInfo(reader);
            try fields.append(self.allocator, field);
        }

        return fields;
    }

    fn parseFieldInfo(self: *RawClassFile, reader: anytype) (ClassFileError || std.mem.Allocator.Error || @TypeOf(reader).Error)!FieldInfo {
        const access_flags = try reader.readInt(u16, .big);
        const name_index = try reader.readInt(u16, .big);
        const descriptor_index = try reader.readInt(u16, .big);
        const attributes_count = try reader.readInt(u16, .big);

        const attributes = try self.parseAttributes(reader, attributes_count);

        return FieldInfo{
            .access_flags = access_flags,
            .name_index = name_index,
            .descriptor_index = descriptor_index,
            .attributes_count = attributes_count,
            .attributes = attributes,
        };
    }

    fn parseMethodInfo(self: *RawClassFile, reader: anytype) (ClassFileError || std.mem.Allocator.Error || @TypeOf(reader).Error)!MethodInfo {
        const access_flags = try reader.readInt(u16, .big);
        const name_index = try reader.readInt(u16, .big);
        const descriptor_index = try reader.readInt(u16, .big);
        const attributes_count = try reader.readInt(u16, .big);

        const attributes = try self.parseAttributes(reader, attributes_count);

        return MethodInfo{
            .access_flags = access_flags,
            .name_index = name_index,
            .descriptor_index = descriptor_index,
            .attributes_count = attributes_count,
            .attributes = attributes,
        };
    }

    fn parseAttributes(self: *RawClassFile, reader: anytype, count: u16) (ClassFileError || std.mem.Allocator.Error || @TypeOf(reader).Error)!std.ArrayList(AttributeInfo) {
        var attributes = try std.ArrayList(AttributeInfo).initCapacity(self.allocator, 0);

        var i: u16 = 0;
        while (i < count) : (i += 1) {
            const attribute = try self.parseAttributeInfo(reader);
            try attributes.append(self.allocator, attribute);
        }

        return attributes;
    }

    fn parseAttributeInfo(self: *RawClassFile, reader: anytype) (ClassFileError || std.mem.Allocator.Error || @TypeOf(reader).Error)!AttributeInfo {
        const attribute_name_index = try reader.readInt(u16, .big);
        const attribute_length = try reader.readInt(u32, .big);

        // Get the attribute name from constant pool to determine type
        const attribute_name = self.getUtf8FromConstantPool(attribute_name_index) catch "";

        const info = if (std.mem.eql(u8, attribute_name, "Code"))
            try self.parseCodeAttribute(reader)
        else if (std.mem.eql(u8, attribute_name, "LineNumberTable"))
            try self.parseLineNumberTableAttribute(reader)
        else if (std.mem.eql(u8, attribute_name, "SourceFile"))
            try self.parseSourceFileAttribute(reader)
        else if (std.mem.eql(u8, attribute_name, "ConstantValue"))
            try self.parseConstantValueAttribute(reader)
        else
            try self.parseUnknownAttribute(reader, attribute_length);

        return AttributeInfo{
            .attribute_name_index = attribute_name_index,
            .attribute_length = attribute_length,
            .info = info,
        };
    }

    fn parseCodeAttribute(self: *RawClassFile, reader: anytype) (ClassFileError || std.mem.Allocator.Error || @TypeOf(reader).Error)!AttributeData {
        const max_stack = try reader.readInt(u16, .big);
        const max_locals = try reader.readInt(u16, .big);
        const code_length = try reader.readInt(u32, .big);

        const code = try self.allocator.alloc(u8, code_length);
        _ = try reader.readAll(code);

        const exception_table_length = try reader.readInt(u16, .big);
        const exception_table = try self.allocator.alloc(ExceptionTableEntry, exception_table_length);

        var i: u16 = 0;
        while (i < exception_table_length) : (i += 1) {
            exception_table[i] = ExceptionTableEntry{
                .start_pc = try reader.readInt(u16, .big),
                .end_pc = try reader.readInt(u16, .big),
                .handler_pc = try reader.readInt(u16, .big),
                .catch_type = try reader.readInt(u16, .big),
            };
        }

        const attributes_count = try reader.readInt(u16, .big);
        const attributes = try self.parseAttributes(reader, attributes_count);

        return AttributeData{ .Code = CodeAttribute{
            .max_stack = max_stack,
            .max_locals = max_locals,
            .code_length = code_length,
            .code = code,
            .exception_table_length = exception_table_length,
            .exception_table = exception_table,
            .attributes_count = attributes_count,
            .attributes = attributes,
        } };
    }

    fn parseLineNumberTableAttribute(self: *RawClassFile, reader: anytype) !AttributeData {
        const line_number_table_length = try reader.readInt(u16, .big);
        const line_number_table = try self.allocator.alloc(LineNumberEntry, line_number_table_length);

        var i: u16 = 0;
        while (i < line_number_table_length) : (i += 1) {
            line_number_table[i] = LineNumberEntry{
                .start_pc = try reader.readInt(u16, .big),
                .line_number = try reader.readInt(u16, .big),
            };
        }

        return AttributeData{ .LineNumberTable = LineNumberTableAttribute{
            .line_number_table_length = line_number_table_length,
            .line_number_table = line_number_table,
        } };
    }

    fn parseSourceFileAttribute(_: *RawClassFile, reader: anytype) !AttributeData {
        const sourcefile_index = try reader.readInt(u16, .big);
        return AttributeData{ .SourceFile = SourceFileAttribute{
            .sourcefile_index = sourcefile_index,
        } };
    }

    fn parseConstantValueAttribute(_: *RawClassFile, reader: anytype) !AttributeData {
        const constantvalue_index = try reader.readInt(u16, .big);
        return AttributeData{ .ConstantValue = ConstantValueAttribute{
            .constantvalue_index = constantvalue_index,
        } };
    }

    fn parseUnknownAttribute(self: *RawClassFile, reader: anytype, length: u32) (std.mem.Allocator.Error || @TypeOf(reader).Error)!AttributeData {
        const data = try self.allocator.alloc(u8, length);
        _ = try reader.readAll(data);
        return AttributeData{ .Unknown = data };
    }

    pub fn getUtf8FromConstantPool(self: *RawClassFile, index: u16) ClassFileError![]const u8 {
        if (index == 0 or index > self.constant_pool.items.len) {
            return ClassFileError.InvalidClassFile;
        }

        const entry = self.constant_pool.items[index - 1]; // Convert to 0-indexed
        return switch (entry) {
            .Utf8 => |bytes| bytes,
            else => ClassFileError.InvalidClassFile,
        };
    }

    pub fn printMethods(self: *RawClassFile) void {
        std.debug.print("\nMethods ({d}):\n", .{self.method_count});

        for (self.methods.items, 0..) |*method, i| {
            std.debug.print("  Method #{d}:\n", .{i});
            std.debug.print("    Access flags: 0x{X:0>4}\n", .{method.access_flags});
            std.debug.print("    Name index: #{d}", .{method.name_index});

            // Try to resolve the name from constant pool
            if (self.getUtf8FromConstantPool(method.name_index)) |name| {
                std.debug.print(" (\"{s}\")", .{name});
            } else |_| {}
            std.debug.print("\n", .{});

            std.debug.print("    Descriptor index: #{d}", .{method.descriptor_index});

            // Try to resolve the descriptor from constant pool
            if (self.getUtf8FromConstantPool(method.descriptor_index)) |descriptor| {
                std.debug.print(" (\"{s}\")", .{descriptor});
            } else |_| {}
            std.debug.print("\n", .{});

            std.debug.print("    Attributes count: {d}\n", .{method.attributes_count});

            if (method.attributes.items.len > 0) {
                self.printAttributes(&method.attributes, 6); // 6 spaces for indentation
            }
            std.debug.print("\n", .{});
        }
    }

    pub fn printFields(self: *RawClassFile) void {
        std.debug.print("\nFields ({d}):\n", .{self.fields_count});

        for (self.fields.items, 0..) |*field, i| {
            std.debug.print("  Field #{d}:\n", .{i});
            std.debug.print("    Access flags: 0x{X:0>4}\n", .{field.access_flags});
            std.debug.print("    Name index: #{d}", .{field.name_index});

            // Try to resolve the name from constant pool
            if (self.getUtf8FromConstantPool(field.name_index)) |name| {
                std.debug.print(" (\"{s}\")", .{name});
            } else |_| {}
            std.debug.print("\n", .{});

            std.debug.print("    Descriptor index: #{d}", .{field.descriptor_index});

            // Try to resolve the descriptor from constant pool
            if (self.getUtf8FromConstantPool(field.descriptor_index)) |descriptor| {
                std.debug.print(" (\"{s}\")", .{descriptor});
            } else |_| {}
            std.debug.print("\n", .{});

            std.debug.print("    Attributes count: {d}\n", .{field.attributes_count});

            if (field.attributes.items.len > 0) {
                self.printAttributes(&field.attributes, 6); // 6 spaces for indentation
            }
            std.debug.print("\n", .{});
        }
    }

    fn printAttributes(self: *RawClassFile, attributes: *std.ArrayList(AttributeInfo), indent: u32) void {
        for (attributes.items, 0..) |*attr, i| {
            self.printIndent(indent);
            std.debug.print("Attribute #{d}:\n", .{i});

            self.printIndent(indent + 2);
            std.debug.print("Name index: #{d}", .{attr.attribute_name_index});

            // Try to resolve attribute name
            if (self.getUtf8FromConstantPool(attr.attribute_name_index)) |name| {
                std.debug.print(" (\"{s}\")", .{name});
            } else |_| {}
            std.debug.print("\n", .{});

            self.printIndent(indent + 2);
            std.debug.print("Length: {d}\n", .{attr.attribute_length});

            switch (attr.info) {
                .Code => |*code| {
                    self.printCodeAttribute(code, indent + 2);
                },
                .LineNumberTable => |*lnt| {
                    self.printLineNumberTableAttribute(lnt, indent + 2);
                },
                .SourceFile => |*sf| {
                    self.printSourceFileAttribute(sf, indent + 2);
                },
                .ConstantValue => |*cv| {
                    self.printConstantValueAttribute(cv, indent + 2);
                },
                .Unknown => |data| {
                    self.printIndent(indent + 2);
                    std.debug.print("Unknown attribute ({d} bytes)\n", .{data.len});
                },
            }
        }
    }

    fn printCodeAttribute(self: *RawClassFile, code: *const CodeAttribute, indent: u32) void {
        self.printIndent(indent);
        std.debug.print("Code Attribute:\n", .{});

        self.printIndent(indent + 2);
        std.debug.print("Max stack: {d}\n", .{code.max_stack});

        self.printIndent(indent + 2);
        std.debug.print("Max locals: {d}\n", .{code.max_locals});

        self.printIndent(indent + 2);
        std.debug.print("Code length: {d}\n", .{code.code_length});

        self.printIndent(indent + 2);
        std.debug.print("Bytecode: \n", .{});
        try decodeBytecode(code.code);
        std.debug.print("\n", .{});

        self.printIndent(indent + 2);
        std.debug.print("Exception table length: {d}\n", .{code.exception_table_length});

        if (code.exception_table_length > 0) {
            for (code.exception_table, 0..) |entry, i| {
                self.printIndent(indent + 4);
                std.debug.print("Exception #{d}: start_pc={d}, end_pc={d}, handler_pc={d}, catch_type=#{d}\n", .{ i, entry.start_pc, entry.end_pc, entry.handler_pc, entry.catch_type });
            }
        }

        self.printIndent(indent + 2);
        std.debug.print("Code attributes count: {d}\n", .{code.attributes_count});

        if (code.attributes.items.len > 0) {
            // Recursively print nested attributes
            self.printAttributes(@constCast(&code.attributes), indent + 4);
        }
    }

    fn printLineNumberTableAttribute(self: *RawClassFile, lnt: *const LineNumberTableAttribute, indent: u32) void {
        self.printIndent(indent);
        std.debug.print("LineNumberTable Attribute:\n", .{});

        self.printIndent(indent + 2);
        std.debug.print("Length: {d}\n", .{lnt.line_number_table_length});

        for (lnt.line_number_table, 0..) |entry, i| {
            self.printIndent(indent + 2);
            std.debug.print("Entry #{d}: start_pc={d}, line_number={d}\n", .{ i, entry.start_pc, entry.line_number });
        }
    }

    fn printSourceFileAttribute(self: *RawClassFile, sf: *const SourceFileAttribute, indent: u32) void {
        self.printIndent(indent);
        std.debug.print("SourceFile Attribute:\n", .{});

        self.printIndent(indent + 2);
        std.debug.print("Source file index: #{d}", .{sf.sourcefile_index});

        if (self.getUtf8FromConstantPool(sf.sourcefile_index)) |filename| {
            std.debug.print(" (\"{s}\")", .{filename});
        } else |_| {}
        std.debug.print("\n", .{});
    }

    fn printConstantValueAttribute(self: *RawClassFile, cv: *const ConstantValueAttribute, indent: u32) void {
        self.printIndent(indent);
        std.debug.print("ConstantValue Attribute:\n", .{});

        self.printIndent(indent + 2);
        std.debug.print("Constant value index: #{d}", .{cv.constantvalue_index});

        // Try to get the actual constant value
        if (cv.constantvalue_index > 0 and cv.constantvalue_index <= self.constant_pool.items.len) {
            const entry = self.constant_pool.items[cv.constantvalue_index - 1];
            switch (entry) {
                .Integer => |value| std.debug.print(" (Integer: {d})", .{value}),
                .Float => |value| std.debug.print(" (Float: {d})", .{value}),
                .Long => |value| std.debug.print(" (Long: {d})", .{value}),
                .Double => |value| std.debug.print(" (Double: {d})", .{value}),
                .String => |string_index| {
                    if (self.getUtf8FromConstantPool(string_index)) |string| {
                        std.debug.print(" (String: \"{s}\")", .{string});
                    } else |_| {}
                },
                else => {},
            }
        }
        std.debug.print("\n", .{});
    }

    pub fn printConstantPool(self: *RawClassFile) void {
        std.debug.print("\nConstant Pool ({d}):\n", .{self.constant_pool_count});

        for (self.constant_pool.items, 0..) |entry, i| {
            std.debug.print("  #{d}: ", .{i + 1}); // Constant pool is 1-indexed

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
                .Class => |name_index| {
                    std.debug.print("Class = #{d}", .{name_index});
                    if (self.getUtf8FromConstantPool(name_index)) |name| {
                        std.debug.print(" (\"{s}\")", .{name});
                    } else |_| {}
                    std.debug.print("\n", .{});
                },
                .String => |string_index| {
                    std.debug.print("String = #{d}", .{string_index});
                    if (self.getUtf8FromConstantPool(string_index)) |string| {
                        std.debug.print(" (\"{s}\")", .{string});
                    } else |_| {}
                    std.debug.print("\n", .{});
                },
                .Fieldref => |fieldref| {
                    std.debug.print("Fieldref = #{d}.#{d}", .{ fieldref.class_index, fieldref.name_and_type_index });
                    self.printFieldrefDetails(fieldref.class_index, fieldref.name_and_type_index);
                    std.debug.print("\n", .{});
                },
                .Methodref => |methodref| {
                    std.debug.print("Methodref = #{d}.#{d}", .{ methodref.class_index, methodref.name_and_type_index });
                    self.printMethodrefDetails(methodref.class_index, methodref.name_and_type_index);
                    std.debug.print("\n", .{});
                },
                .InterfaceMethodref => |interface_methodref| {
                    std.debug.print("InterfaceMethodref = #{d}.#{d}", .{ interface_methodref.class_index, interface_methodref.name_and_type_index });
                    self.printMethodrefDetails(interface_methodref.class_index, interface_methodref.name_and_type_index);
                    std.debug.print("\n", .{});
                },
                .NameAndType => |name_and_type| {
                    std.debug.print("NameAndType = #{d}:#{d}", .{ name_and_type.name_index, name_and_type.descriptor_index });
                    self.printNameAndTypeDetails(name_and_type.name_index, name_and_type.descriptor_index);
                    std.debug.print("\n", .{});
                },
            }
        }
    }

    fn printFieldrefDetails(self: *RawClassFile, class_index: u16, name_and_type_index: u16) void {
        if (self.getClassNameFromIndex(class_index)) |class_name| {
            if (self.getNameAndTypeFromIndex(name_and_type_index)) |name_and_type| {
                std.debug.print(" ({s}.{s}:{s})", .{ class_name, name_and_type.name, name_and_type.descriptor });
            } else |_| {
                std.debug.print(" ({s}.<invalid>)", .{class_name});
            }
        } else |_| {}
    }

    fn printMethodrefDetails(self: *RawClassFile, class_index: u16, name_and_type_index: u16) void {
        if (self.getClassNameFromIndex(class_index)) |class_name| {
            if (self.getNameAndTypeFromIndex(name_and_type_index)) |name_and_type| {
                std.debug.print(" ({s}.{s}{s})", .{ class_name, name_and_type.name, name_and_type.descriptor });
            } else |_| {
                std.debug.print(" ({s}.<invalid>)", .{class_name});
            }
        } else |_| {}
    }

    fn printNameAndTypeDetails(self: *RawClassFile, name_index: u16, descriptor_index: u16) void {
        const name = self.getUtf8FromConstantPool(name_index) catch "<invalid>";
        const descriptor = self.getUtf8FromConstantPool(descriptor_index) catch "<invalid>";
        std.debug.print(" ({s}:{s})", .{ name, descriptor });
    }

    pub fn getClassNameFromIndex(self: *RawClassFile, index: u16) ClassFileError![]const u8 {
        if (index == 0 or index > self.constant_pool.items.len) {
            return ClassFileError.InvalidClassFile;
        }

        const entry = self.constant_pool.items[index - 1];
        return switch (entry) {
            .Class => |name_index| self.getUtf8FromConstantPool(name_index),
            else => ClassFileError.InvalidClassFile,
        };
    }

    fn getNameAndTypeFromIndex(self: *RawClassFile, index: u16) ClassFileError!struct { name: []const u8, descriptor: []const u8 } {
        if (index == 0 or index > self.constant_pool.items.len) {
            return ClassFileError.InvalidClassFile;
        }

        const entry = self.constant_pool.items[index - 1];
        return switch (entry) {
            .NameAndType => |name_and_type| .{
                .name = self.getUtf8FromConstantPool(name_and_type.name_index) catch return ClassFileError.InvalidClassFile,
                .descriptor = self.getUtf8FromConstantPool(name_and_type.descriptor_index) catch return ClassFileError.InvalidClassFile,
            },
            else => ClassFileError.InvalidClassFile,
        };
    }

    fn printIndent(self: *RawClassFile, spaces: u32) void {
        _ = self; // Suppress unused parameter warning
        var i: u32 = 0;
        while (i < spaces) : (i += 1) {
            std.debug.print(" ", .{});
        }
    }
};
