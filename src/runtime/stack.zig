const std = @import("std");
const MockObject = @import("mocks.zig").MockObject;
const Heap = @import("heap.zig").Heap;

pub const StackValueType = enum {
    reference,
    int,
    long,
    float,
    double,
    return_address,
};

pub const StackValue = struct {
    type: StackValueType,
    value: union(StackValueType) {
        reference: ?*anyopaque, // Object reference or null
        int: i32,
        long: i64,
        float: f32,
        double: f64,
        return_address: u32, // Bytecode offset
    },
};

pub const CallFrame = struct {
    allocator: std.mem.Allocator,
    pc: u8,
    locals: std.ArrayList(StackValue),
    stack: std.ArrayList(StackValue),
    objects: std.ArrayList(*MockObject),
    heap: *Heap,

    pub fn init(allocator: std.mem.Allocator, max_locals: u16, max_stack: u16, heap: *Heap) !*CallFrame {
        const frame = try allocator.create(CallFrame);
        frame.* = CallFrame{
            .allocator = allocator,
            .pc = 0,
            .locals = try std.ArrayList(StackValue).initCapacity(allocator, max_locals), // Use actual capacity needed
            .stack = try std.ArrayList(StackValue).initCapacity(allocator, max_stack), // Use actual capacity needed
            .objects = try std.ArrayList(*MockObject).initCapacity(allocator, 0),
            .heap = heap,
        };
        return frame;
    }

    pub fn initWithLocals(allocator: std.mem.Allocator, locals: std.ArrayList(StackValue), max_stack: u8, heap: *Heap) !*CallFrame {
        const frame = try allocator.create(CallFrame);
        var locals_copy = try std.ArrayList(StackValue).initCapacity(allocator, locals.items.len);
        try locals_copy.appendSlice(allocator, locals.items);
        frame.* = CallFrame{
            .allocator = allocator,
            .pc = 0,
            .locals = locals_copy,
            .stack = try std.ArrayList(StackValue).initCapacity(allocator, max_stack), // Use actual capacity needed
            .objects = try std.ArrayList(*MockObject).initCapacity(allocator, 0),
            .heap = heap,
        };
        return frame;
    }

    pub fn initWithThis(allocator: std.mem.Allocator, this: StackValue, locals: std.ArrayList(StackValue), max_stack: u8, heap: *Heap) !*CallFrame {
        const frame = try allocator.create(CallFrame);
        var locals_copy = try std.ArrayList(StackValue).initCapacity(allocator, locals.items.len + 1);
        try locals_copy.append(allocator, this); // this goes in locals[0]
        try locals_copy.appendSlice(allocator, locals.items); // args go in locals[1..]
        frame.* = CallFrame{
            .allocator = allocator,
            .pc = 0,
            .locals = locals_copy,
            .stack = try std.ArrayList(StackValue).initCapacity(allocator, max_stack),
            .objects = try std.ArrayList(*MockObject).initCapacity(allocator, 0),
            .heap = heap,
        };
        return frame;
    }

    pub fn deinit(self: *CallFrame) void {
        for (self.objects.items) |obj| {
            self.allocator.destroy(obj);
        }
        self.objects.deinit(self.allocator);
        self.locals.deinit(self.allocator);
        self.stack.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn push(self: *CallFrame, value: StackValue) !void {
        try self.stack.append(self.allocator, value);
    }

    pub fn pop(self: *CallFrame) ?StackValue {
        return self.stack.pop();
    }

    pub fn peek(self: *CallFrame) ?StackValue {
        if (self.stack.items.len == 0) return null;
        return self.stack.items[self.stack.items.len - 1];
    }

    pub fn inc_pc(self: *CallFrame, count: u8) void {
        self.pc += count;
    }
};
