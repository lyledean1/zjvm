const std = @import("std");
const bc = @import("../class/bytecode.zig");
const class_reader = @import("../class/reader.zig");
const class = @import("../class/reader.zig").RawClassFile;
const code_attribute = @import("../class/reader.zig").CodeAttribute;
const isMethod = @import("../class/constant_pool.zig").isMethod;
const cp = @import("../class/constant_pool.zig");
const ConstantPoolInfo = @import("../class/constant_pool.zig").ConstantPoolInfo;
const KlassRepo = @import("./klass.zig").KlassRepo;
const Field = @import("./field.zig").Field;
const Object = @import("./object.zig").Object;
const Heap = @import("./heap.zig").Heap;
const MockObject = @import("./mocks.zig").MockObject;
const MockPrintStream = @import("./mocks.zig").MockPrintStream;
const MockStringBuilder = @import("./mocks.zig").MockStringBuilder;
const StackValue = @import("./stack.zig").StackValue;
const StackValueType = @import("./stack.zig").StackValueType;
const CallFrame = @import("stack.zig").CallFrame;

pub fn execute(cf: *CallFrame, klass_name: []u8, klass_repo: *KlassRepo, code: []u8, constant_pool: std.ArrayList(ConstantPoolInfo), debug: bool) !?StackValue {
    const bytecode = code;
    while (cf.pc < bytecode.len) {
        const pc = cf.pc;
        const opcode_byte = bytecode[pc];
        const opcode = std.meta.intToEnum(bc.Opcode, opcode_byte) catch bc.Opcode.nop;
        const info = bc.getInstructionInfo(opcode);

        if (debug) {
            std.debug.print("0x{x:0>2}: {s} for class {s}\n", .{ opcode_byte, info.name, klass_name });
        }
        switch (opcode) {
            .getstatic => {
                const index = (@as(u16, bytecode[pc + 1]) << 8) | bytecode[pc + 2];
                const entry = constant_pool.items[index - 1];
                try getStatic(cf, klass_repo, constant_pool, entry);
            },
            .putstatic => {
                const index = (@as(u16, bytecode[pc + 1]) << 8) | bytecode[pc + 2];
                const entry = constant_pool.items[index - 1];
                try putStatic(cf, klass_repo, constant_pool, entry);
            },
            .putfield => {
                const index = (@as(u16, bytecode[pc + 1]) << 8) | bytecode[pc + 2];
                const entry = constant_pool.items[index - 1];
                try putField(cf, constant_pool, entry);
            },
            .getfield => {
                const index = (@as(u16, bytecode[pc + 1]) << 8) | bytecode[pc + 2];
                const entry = constant_pool.items[index - 1];
                try getField(cf, constant_pool, entry);
            },
            .ldc => {
                const index = bytecode[pc + 1];
                const entry = constant_pool.items[index - 1];
                try loadConstant(cf, constant_pool, entry);
            },
            .new => {
                const index = (@as(u16, bytecode[pc + 1]) << 8) | bytecode[pc + 2];
                const entry = constant_pool.items[index - 1];
                try newObject(cf, klass_repo, constant_pool, entry);
            },
            .invokevirtual => {
                const index = (@as(u16, bytecode[pc + 1]) << 8) | bytecode[pc + 2];
                const entry = constant_pool.items[index - 1];
                try invokeVirtual(cf, klass_name, klass_repo, constant_pool, entry, debug);
            },
            .iconst_m1 => try pushConstantInt(cf, -1),
            .iconst_0 => try pushConstantInt(cf, 0),
            .iconst_1 => try pushConstantInt(cf, 1),
            .iconst_2 => try pushConstantInt(cf, 2),
            .iconst_3 => try pushConstantInt(cf, 3),
            .iconst_4 => try pushConstantInt(cf, 4),
            .iconst_5 => try pushConstantInt(cf, 5),
            .fconst_0 => try pushConstantFloat(cf, 0),
            .fconst_1 => try pushConstantFloat(cf, 0),
            .fconst_2 => try pushConstantFloat(cf, 0),
            .bipush => {
                const value = @as(i8, @bitCast(bytecode[pc + 1]));
                try pushConstantInt(cf, @as(i32, value));
            },
            .iinc => {
                const index = bytecode[pc + 1];
                const increment = @as(i8, @bitCast(bytecode[pc + 2]));
                try incrementLocal(cf, index, @as(i32, increment));
            },
            .iload_0 => try loadLocal(cf, 0),
            .iload_1 => try loadLocal(cf, 1),
            .iload_2 => try loadLocal(cf, 2),
            .iload_3 => try loadLocal(cf, 3),
            .iadd => try doArithmetic(cf, '+'),
            .isub => try doArithmetic(cf, '-'),
            .imul => try doArithmetic(cf, '*'),
            .idiv => try doArithmetic(cf, '/'),
            .irem => try doArithmetic(cf, '%'),
            .ireturn => return cf.pop().?,
            .aload_0 => try loadLocal(cf, 0),
            .aload_1 => try loadLocal(cf, 1),
            .aload_2 => try loadLocal(cf, 2),
            .aload_3 => try loadLocal(cf, 3),
            .invokestatic => {
                const index = (@as(u16, bytecode[pc + 1]) << 8) | bytecode[pc + 2];
                const entry = constant_pool.items[index - 1];
                try invokeStatic(cf, klass_name, klass_repo, constant_pool, entry, debug);
            },
            .invokespecial => {
                const index = (@as(u16, bytecode[pc + 1]) << 8) | bytecode[pc + 2];
                const entry = constant_pool.items[index - 1];
                try invokeSpecial(cf, klass_name, klass_repo, constant_pool, entry, debug);
            },
            .dup => {
                const eval = cf.peek().?;
                try cf.push(eval);
            },
            .astore_0 => try storeLocal(cf, 0),
            .astore_1 => try storeLocal(cf, 1),
            .astore_2 => try storeLocal(cf, 2),
            .astore_3 => try storeLocal(cf, 3),
            .istore_0 => try storeLocal(cf, 0),
            .istore_1 => try storeLocal(cf, 1),
            .istore_2 => try storeLocal(cf, 2),
            .istore_3 => try storeLocal(cf, 3),
            .ifeq => try doConditionalJump(cf, bytecode, pc, "=="),
            .ifne => try doConditionalJump(cf, bytecode, pc, "!="),
            .ifgt => try doConditionalJump(cf, bytecode, pc, ">"),
            .ifge => try doConditionalJump(cf, bytecode, pc, ">="),
            .iflt => try doConditionalJump(cf, bytecode, pc, "<"),
            .ifle => try doConditionalJump(cf, bytecode, pc, "<="),
            .if_icmpeq => try doConditionalCompareJump(cf, bytecode, pc, "=="),
            .if_icmpne => try doConditionalCompareJump(cf, bytecode, pc, "!="),
            .if_icmpge => try doConditionalCompareJump(cf, bytecode, pc, ">="),
            .if_icmple => try doConditionalCompareJump(cf, bytecode, pc, "<="),
            .if_icmplt => try doConditionalCompareJump(cf, bytecode, pc, "<"),
            .if_icmpgt => try doConditionalCompareJump(cf, bytecode, pc, ">"),
            .nop => {
                // Do nothing - no op instruction
            },
            .goto => {
                const offset = (@as(i16, bytecode[pc + 1]) << 8) + @as(i16, bytecode[pc + 2]);
                cf.pc = @intCast(@as(i32, @intCast(cf.pc)) + offset);
                continue;
            },
            .@"return" => return null,
            else => {
                std.debug.print("\n", .{});
                std.debug.print("opcode not implemented 0x{x:0>2}: {s}\n", .{ opcode_byte, info.name });
                return error.OpcodeNotImplemented;
            },
        }

        if (debug) {
            std.debug.print("\n", .{});
        }
        cf.inc_pc(1 + info.operand_count);
    }
    return null;
}

fn loadLocal(cf: *CallFrame, index: usize) !void {
    if (cf.locals.items.len <= index) {
        std.debug.print("ERROR: load but no local variables at index {d}\n", .{index});
        return;
    }

    const local_val = cf.locals.items[index];
    try cf.push(local_val);
}

fn pushConstantInt(cf: *CallFrame, value: i32) !void {
    try cf.push(StackValue{
        .type = .int,
        .value = .{ .int = value },
    });
}

fn pushConstantFloat(cf: *CallFrame, value: f32) !void {
    try cf.push(StackValue{
        .type = .float,
        .value = .{ .float = value },
    });
}

fn storeLocal(cf: *CallFrame, index: usize) !void {
    const value = cf.pop().?;

    while (cf.locals.items.len <= index) {
        try cf.locals.append(cf.allocator, StackValue{ .type = .reference, .value = .{ .reference = null } });
    }

    cf.locals.items[index] = value;
}

fn incrementLocal(cf: *CallFrame, index: usize, increment: i32) !void {
    while (cf.locals.items.len <= index) {
        try cf.locals.append(cf.allocator, StackValue{ .type = .int, .value = .{ .int = 0 } });
    }

    if (cf.locals.items[index].type != .int) {
        return error.InvalidLocalVariableType;
    }

    cf.locals.items[index].value.int += increment;
}

fn doArithmetic(cf: *CallFrame, comptime op: u8) !void {
    const value_two = cf.pop().?;
    const value_one = cf.pop().?;

    const result = switch (op) {
        '+' => value_one.value.int + value_two.value.int,
        '-' => value_one.value.int - value_two.value.int,
        '*' => value_one.value.int * value_two.value.int,
        '/' => @divTrunc(value_one.value.int, value_two.value.int),
        '%' => @rem(value_one.value.int, value_two.value.int),
        else => unreachable,
    };

    try pushConstantInt(cf, result);
}

fn doConditionalJump(cf: *CallFrame, bytecode: []u8, pc: usize, comptime op: []const u8) !void {
    const value = cf.pop().?;
    const offset = @as(i16, @bitCast((@as(u16, bytecode[pc + 1]) << 8) | bytecode[pc + 2]));
    
    const should_jump = if (std.mem.eql(u8, op, "=="))
        value.value.int == 0
    else if (std.mem.eql(u8, op, "!="))
        value.value.int != 0
    else if (std.mem.eql(u8, op, ">"))
        value.value.int > 0
    else if (std.mem.eql(u8, op, ">="))
        value.value.int >= 0
    else if (std.mem.eql(u8, op, "<"))
        value.value.int < 0
    else if (std.mem.eql(u8, op, "<="))
        value.value.int <= 0
    else
        unreachable;
    
    if (should_jump) {
        cf.inc_pc(@intCast(offset - 3));
    }
}

fn doConditionalCompareJump(cf: *CallFrame, bytecode: []u8, pc: usize, comptime op: []const u8) !void {
    const value_two = cf.pop().?;
    const value_one = cf.pop().?;
    const offset = @as(i16, @bitCast((@as(u16, bytecode[pc + 1]) << 8) | bytecode[pc + 2]));
    
    const should_jump = if (std.mem.eql(u8, op, "=="))
        value_one.value.int == value_two.value.int
    else if (std.mem.eql(u8, op, "!="))
        value_one.value.int != value_two.value.int
    else if (std.mem.eql(u8, op, ">"))
        value_one.value.int > value_two.value.int
    else if (std.mem.eql(u8, op, ">="))
        value_one.value.int >= value_two.value.int
    else if (std.mem.eql(u8, op, "<"))
        value_one.value.int < value_two.value.int
    else if (std.mem.eql(u8, op, "<="))
        value_one.value.int <= value_two.value.int
    else
        unreachable;
    
    if (should_jump) {
        cf.inc_pc(@intCast(offset - 3));
    }
}

fn loadConstant(cf: *CallFrame, constant_pool: std.ArrayList(ConstantPoolInfo), entry: ConstantPoolInfo) !void {
    switch (entry) {
        .String => |string_index| {
            if (cp.getUtf8FromConstantPool(constant_pool.items, string_index)) |string_bytes| {
                try cf.push(StackValue{
                    .type = .reference,
                    .value = .{ .reference = @ptrCast(@constCast(string_bytes.ptr)) },
                });
            } else |_| {
                return error.StringNotFound;
            }
        },
        else => {
            return error.ConstantNotImplemented;
        },
    }
}

fn getStatic(cf: *CallFrame, klass_repo: *KlassRepo, constant_pool: std.ArrayList(ConstantPoolInfo), entry: ConstantPoolInfo) !void {
    // Handle System.out special case
    // todo - not use mocks
    if (isMethod("java/lang/System", "out", constant_pool.items, entry)) {
        const mock_stream = try cf.allocator.create(MockObject);
        mock_stream.* = MockPrintStream;
        try cf.objects.append(cf.allocator, mock_stream);
        try cf.push(StackValue{
            .type = .reference,
            .value = .{ .reference = @ptrCast(mock_stream) },
        });
        return;
    }

    if (entry != .Fieldref) return;

    const fieldref = entry.Fieldref;
    const class_name = try cp.getClassName(constant_pool.items, entry);
    const field_info = try cp.getNameAndTypeFromIndex(constant_pool.items, fieldref.name_and_type_index);

    if (klass_repo.getKlass(class_name)) |clz| {
        var buffer: [256]u8 = undefined;
        const key = try std.fmt.bufPrint(&buffer, "{s}.{s}:{s}", .{ class_name, field_info.name, field_info.descriptor });
        if (try clz.get_s_val(key)) |val| {
            try cf.push(val);
        } else {
            return error.GetStaticKeyNotFound;
        }
    }
}

fn putStatic(cf: *CallFrame, klass_repo: *KlassRepo, constant_pool: std.ArrayList(ConstantPoolInfo), entry: ConstantPoolInfo) !void {
    if (entry != .Fieldref) return;

    const fieldref = entry.Fieldref;
    const class_name = try cp.getClassNameFromIndex(constant_pool.items, fieldref.class_index);
    const field_info = try cp.getNameAndTypeFromIndex(constant_pool.items, fieldref.name_and_type_index);

    if (klass_repo.getKlass(class_name)) |clz| {
        var buffer: [256]u8 = undefined;
        const key = try std.fmt.bufPrint(&buffer, "{s}.{s}:{s}", .{ class_name, field_info.name, field_info.descriptor });
        const value = cf.pop().?;
        try clz.put_s_val(cf.allocator, key, value);
    } else {
        std.debug.print("\n Klass {s} not found \n", .{class_name});
        return error.KlassNotFound;
    }
}

fn getField(cf: *CallFrame, constant_pool: std.ArrayList(ConstantPoolInfo), entry: ConstantPoolInfo) !void {
    const field_name = try cp.getFieldName(constant_pool.items, entry);
    const field_type = try cp.getFieldType(constant_pool.items, entry);

    const objectref = cf.pop().?;

    if (objectref.value.reference == null) {
        return error.NullPointerException;
    }

    const object_id = @as(u32, @intCast(@intFromPtr(objectref.value.reference.?)));
    const object = cf.heap.getObjectPtr(object_id).?;

    var buffer: [256]u8 = undefined;
    const field_key = try std.fmt.bufPrint(&buffer, "{s}:{s}", .{ field_name, field_type });
    if (object.getField(field_key)) |field_value| {
        try cf.push(field_value);
    } else {
        return error.FieldNotFound;
    }
}

fn putField(cf: *CallFrame, constant_pool: std.ArrayList(ConstantPoolInfo), entry: ConstantPoolInfo) !void {
    const field_name = try cp.getFieldName(constant_pool.items, entry);
    const field_type = try cp.getFieldType(constant_pool.items, entry);

    const value = cf.pop().?;
    const objectref = cf.pop().?;

    if (objectref.value.reference == null) {
        return error.NullPointerException;
    }

    const object_id = @as(u32, @intCast(@intFromPtr(objectref.value.reference.?)));
    const object = cf.heap.getObjectPtr(object_id).?;

    var buffer: [256]u8 = undefined;
    const field_key = try std.fmt.bufPrint(&buffer, "{s}:{s}", .{ field_name, field_type });
    try object.setField(cf.allocator, field_key, value);
}

fn newObject(cf: *CallFrame, klass_repo: *KlassRepo, constant_pool: std.ArrayList(ConstantPoolInfo), entry: ConstantPoolInfo) !void {
    const class_name = try cp.getClassName(constant_pool.items, entry);

    // Mock StringBuilder for time being
    if (std.mem.eql(u8, class_name, "java/lang/StringBuilder")) {
        const mock_stringbuilder = try cf.allocator.create(MockObject);
        mock_stringbuilder.* = MockStringBuilder;
        try cf.objects.append(cf.allocator, mock_stringbuilder);
        try cf.push(StackValue{
            .type = .reference,
            .value = .{ .reference = @ptrCast(mock_stringbuilder) },
        });
        return;
    }

    if (klass_repo.getKlass(class_name)) |kls| {
        const object_id = try cf.heap.createObjectWithKlass(kls);
        try cf.push(StackValue{
            .type = .reference,
            .value = .{ .reference = @ptrFromInt(object_id) },
        });
    } else {
        std.debug.print("\n Klass {s} not found \n", .{class_name});
        return error.KlassNotFound;
    }
}

fn collectMethodArguments(cf: *CallFrame, param_count: usize) !std.ArrayList(StackValue) {
    var args = try std.ArrayList(StackValue).initCapacity(cf.allocator, param_count);
    var i: usize = 0;
    while (i < param_count) : (i += 1) {
        try args.insert(cf.allocator, 0, cf.pop().?);
    }
    return args;
}

fn executeMethod(cf: *CallFrame, klass_name: []u8, klass_repo: *KlassRepo, method_name: []const u8, method_descriptor: []const u8, target_class_name: []const u8, args: std.ArrayList(StackValue), this_ref: ?StackValue, debug: bool) anyerror!void {
    if (klass_repo.getKlass(target_class_name)) |kls| {
        var buffer: [256]u8 = undefined;
        const method_key = try std.fmt.bufPrint(&buffer, "{s}:{s}", .{ method_name, method_descriptor });

        if (kls.m_name_desc_lookup.get(method_key)) |method_index| {
            const method = kls.methods[method_index];

            const call_frame = if (this_ref) |this_val|
                try CallFrame.initWithThis(cf.allocator, this_val, args, 0, cf.heap)
            else
                try CallFrame.initWithLocals(cf.allocator, args, 0, cf.heap);

            defer call_frame.deinit();
            const result = try execute(call_frame, klass_name, klass_repo, method.code, kls.constant_pool, debug);
            if (result) |val| {
                try cf.push(val);
            }
        }
    } else {
        std.debug.print("\n Method {s} not found in class {s}:{s} \n", .{method_name, method_descriptor, target_class_name});
        return error.NoMethodFound;
    }
}

fn invokeStatic(cf: *CallFrame, klass_name: []u8, klass_repo: *KlassRepo, constant_pool: std.ArrayList(ConstantPoolInfo), entry: ConstantPoolInfo, debug: bool) anyerror!void {
    const descriptor = try cp.getMethodDescriptor(constant_pool.items, entry);
    const name = try cp.getMethodName(constant_pool.items, entry);
    const target_class_name = try cp.getClassName(constant_pool.items, entry);
    const param_count = cp.countMethodParameters(descriptor);

    var args = try collectMethodArguments(cf, param_count);
    defer args.deinit(cf.allocator);

    try executeMethod(cf, klass_name, klass_repo, name, descriptor, target_class_name, args, null, debug);
}

fn invokeVirtual(cf: *CallFrame, klass_name: []u8, klass_repo: *KlassRepo, constant_pool: std.ArrayList(ConstantPoolInfo), entry: ConstantPoolInfo, debug: bool) anyerror!void {
    // Handle println
    if (isMethod("java/io/PrintStream", "println", constant_pool.items, entry)) {
        const arg = cf.pop().?;
        const stream_obj = cf.pop().?;
        if (stream_obj.type == .reference and stream_obj.value.reference != null) {
            const mock_stream = @as(*const MockObject, @ptrCast(@alignCast(stream_obj.value.reference.?)));
            var println_args = [_]StackValue{arg};
            mock_stream.invokeMethod("println", println_args[0..]);
        }
        return;
    }

    // Handle StringBuilder methods
    if (isMethod("java/lang/StringBuilder", "append", constant_pool.items, entry)) {
        const arg = cf.pop().?;
        const sb_obj = cf.pop().?;
        if (sb_obj.type == .reference and sb_obj.value.reference != null) {
            const mock_sb = @as(*const MockObject, @ptrCast(@alignCast(sb_obj.value.reference.?)));
            var append_args = [_]StackValue{arg};
            mock_sb.invokeMethod("append", append_args[0..]);
            // Return the StringBuilder object for method chaining
            try cf.push(sb_obj);
        }
        return;
    }

    if (isMethod("java/lang/StringBuilder", "toString", constant_pool.items, entry)) {
        const sb_obj = cf.pop().?;
        if (sb_obj.type == .reference and sb_obj.value.reference != null) {
            const mock_sb = @as(*const MockObject, @ptrCast(@alignCast(sb_obj.value.reference.?)));
            var empty_args = [_]StackValue{};
            mock_sb.invokeMethod("toString", empty_args[0..]);
            // Push a mock string result
            try cf.push(StackValue{
                .type = .reference,
                .value = .{ .reference = @ptrCast(@constCast("".ptr)) },
            });
        }
        return;
    }

    const descriptor = try cp.getMethodDescriptor(constant_pool.items, entry);
    const name = try cp.getMethodName(constant_pool.items, entry);
    const target_class_name = try cp.getClassName(constant_pool.items, entry);
    const param_count = cp.countMethodParameters(descriptor);

    var args = try collectMethodArguments(cf, param_count);
    defer args.deinit(cf.allocator);

    const this = cf.pop().?;

    // Noop
    if (std.mem.eql(u8, target_class_name, "java/lang/Object") and
        std.mem.eql(u8, name, "<init>") and
        std.mem.eql(u8, descriptor, "()V"))
    {
        return; // noop
    }

    try executeMethod(cf, klass_name, klass_repo, name, descriptor, target_class_name, args, this, debug);
}

fn invokeSpecial(cf: *CallFrame, klass_name: []u8, klass_repo: *KlassRepo, constant_pool: std.ArrayList(ConstantPoolInfo), entry: ConstantPoolInfo, debug: bool) anyerror!void {
    const descriptor = try cp.getMethodDescriptor(constant_pool.items, entry);
    const name = try cp.getMethodName(constant_pool.items, entry);
    const target_class_name = try cp.getClassName(constant_pool.items, entry);
    const param_count = cp.countMethodParameters(descriptor);

    var args = try collectMethodArguments(cf, param_count);
    defer args.deinit(cf.allocator);

    const this = cf.pop().?;

    // Noop for Object constructor
    if (std.mem.eql(u8, target_class_name, "java/lang/Object") and
        std.mem.eql(u8, name, "<init>") and
        std.mem.eql(u8, descriptor, "()V"))
    {
        return;
    }

    // Handle StringBuilder constructor
    if (std.mem.eql(u8, target_class_name, "java/lang/StringBuilder") and
        std.mem.eql(u8, name, "<init>"))
    {
        // Mock StringBuilder constructor - just return (no-op)
        return;
    }

    // For regular heap objects, try to get from heap
    const ptr_value = @intFromPtr(this.value.reference.?);
    if (ptr_value <= std.math.maxInt(u32)) {
        const object_id = @as(u32, @intCast(ptr_value));
        if (cf.heap.getObject(object_id)) |object| {
            const object_klass = object.class_name;
            try executeMethod(cf, klass_name, klass_repo, name, descriptor, object_klass, args, this, debug);
            return;
        }
    }

    // If we get here, it's likely a mock object - just return for now
    return;
}

fn printOperandCount(info: bc.InstructionInfo, bytecode: []u8, i: usize) void {
    std.debug.print(" ", .{});
    var j: u8 = 1;
    while (j <= info.operand_count) : (j += 1) {
        std.debug.print("{X:0>2}", .{bytecode[i + j]});
        if (j < info.operand_count) std.debug.print(" ", .{});
    }
}
