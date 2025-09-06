const std = @import("std");
const Object = @import("object.zig").Object;
const StackValue = @import("stack.zig").StackValue;

pub const Heap = struct {
    next_object_id: u32,
    objects: std.AutoHashMap(u32, Object),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Heap {
        return Heap{
            .next_object_id = 1,
            .objects = std.AutoHashMap(u32, Object).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Heap) void {
        var iterator = self.objects.valueIterator();
        while (iterator.next()) |object| {
            object.deinit(self.allocator);
        }
        self.objects.deinit();
    }

    pub fn getObjectId(self: *Heap) u32 {
        return self.next_object_id;
    }

    pub fn addObject(self: *Heap, object: Object) !u32 {
        const id = self.next_object_id;
        try self.objects.put(id, object);
        self.next_object_id += 1;
        return id;
    }

    pub fn getObject(self: *Heap, id: u32) ?Object {
        return self.objects.get(id);
    }

    pub fn getObjectPtr(self: *Heap, id: u32) ?*Object {
        return self.objects.getPtr(id);
    }

    pub fn createObject(self: *Heap, class_name: []const u8) !u32 {
        const object_id = self.next_object_id;
        const object = Object.init(self.allocator, class_name, object_id);
        try self.objects.put(object_id, object);
        self.next_object_id += 1;
        return object_id;
    }

    pub fn createObjectWithKlass(self: *Heap, klass: *const @import("klass.zig").Klass) !u32 {
        const object_id = self.next_object_id;
        var object = Object.init(self.allocator, klass.name, object_id);

        for (klass.i_fields) |field| {
            const default_value = getDefaultValue(field.desc);
            const field_key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ field.name, field.desc });
            try object.instance_fields.put(field_key, default_value);
        }

        try self.objects.put(object_id, object);
        self.next_object_id += 1;
        return object_id;
    }
};

fn getDefaultValue(descriptor: []const u8) StackValue {
    return switch (descriptor[0]) {
        'I' => StackValue{ .type = .int, .value = .{ .int = 0 } },
        'J' => StackValue{ .type = .long, .value = .{ .long = 0 } },
        'F' => StackValue{ .type = .float, .value = .{ .float = 0.0 } },
        'D' => StackValue{ .type = .double, .value = .{ .double = 0.0 } },
        'L', '[' => StackValue{ .type = .reference, .value = .{ .reference = null } },
        else => StackValue{ .type = .reference, .value = .{ .reference = null } },
    };
}
