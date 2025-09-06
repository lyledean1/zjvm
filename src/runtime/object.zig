const std = @import("std");
const StackValue = @import("stack.zig").StackValue;

pub const Object = struct {
    live: bool,
    class_name: []const u8,
    instance_fields: std.StringHashMap(StackValue),
    object_id: u32,

    pub fn init(allocator: std.mem.Allocator, class_name: []const u8, object_id: u32) Object {
        return Object{
            .live = true,
            .class_name = class_name,
            .instance_fields = std.StringHashMap(StackValue).init(allocator),
            .object_id = object_id,
        };
    }

    pub fn deinit(self: *Object, allocator: std.mem.Allocator) void {
        var iterator = self.instance_fields.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.instance_fields.deinit();
    }

    pub fn setField(self: *Object, allocator: std.mem.Allocator, key: []u8, value: StackValue) !void {
        const result = try self.instance_fields.getOrPut(key);
        if (result.found_existing) {
            // Key already exists, just update the value
            result.value_ptr.* = value;
        } else {
            // New key, create owned copy
            const owned_name = try allocator.dupe(u8, key);
            result.key_ptr.* = owned_name;
            result.value_ptr.* = value;
        }
    }

    pub fn getField(self: *Object, key: []u8) ?StackValue {
        return self.instance_fields.get(key);
    }
};
