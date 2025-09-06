const std = @import("std");
const cp = @import("../class/constant_pool.zig");
const Method = @import("./method.zig").Method;
const Field = @import("./field.zig").Field;
const ConstantPoolInfo = @import("../class/constant_pool.zig").ConstantPoolInfo;
const StackValue = @import("stack.zig").StackValue;
const CallFrame = @import("stack.zig").CallFrame;
const vm = @import("vm.zig");

pub const Klass = struct {
    id: usize,
    initialised: bool,
    name: []u8,
    flag: u16,
    constant_pool: std.ArrayList(ConstantPoolInfo),
    methods: []Method,
    i_fields: []Field,
    s_fields: []Field,
    s_field_vals: std.StringHashMap(StackValue),
    m_name_desc_lookup: std.StringHashMap(usize),
    f_name_desc_lookup: std.StringHashMap(usize),

    pub fn deinit(self: *Klass, allocator: std.mem.Allocator) void {
        allocator.free(self.name);

        // Free the deep-cloned constant pool entries
        for (self.constant_pool.items) |entry| {
            switch (entry) {
                .Utf8 => |bytes| allocator.free(bytes),
                else => {}, // Other types don't need special cleanup
            }
        }
        self.constant_pool.deinit(allocator);

        for (self.methods) |*method| {
            allocator.free(method.klass_name);
            allocator.free(method.name);
            allocator.free(method.name_desc);
            allocator.free(method.code);
        }
        allocator.free(self.methods);

        for (self.i_fields) |*field| {
            allocator.free(field.klass_name);
            allocator.free(field.name);
            allocator.free(field.desc);
        }
        allocator.free(self.i_fields);

        for (self.s_fields) |*field| {
            allocator.free(field.klass_name);
            allocator.free(field.name);
            allocator.free(field.desc);
        }
        allocator.free(self.s_fields);

        var field_iterator = self.f_name_desc_lookup.iterator();
        while (field_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }

        var s_field_iterator = self.s_field_vals.iterator();
        while (s_field_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }

        self.m_name_desc_lookup.deinit();
        self.f_name_desc_lookup.deinit();
        self.s_field_vals.deinit();
    }

    pub fn put_s_val(self: *Klass, allocator: std.mem.Allocator, key: []const u8, val: StackValue) !void {
        const owned_key = try allocator.dupe(u8, key);
        try self.s_field_vals.put(owned_key, val);
    }

    pub fn get_s_val(self: *Klass, key: []u8) !?StackValue {
        return self.s_field_vals.get(key);
    }

    pub fn get_method(self: *const Klass, key: []u8) ?Method {
        if (self.m_name_desc_lookup.get(key)) |index| {
            if (index > self.methods.len) {
                return null;
            }
            return self.methods[index];
        }
        return null;
    }

    pub fn get_constant_pool(self: *const Klass) std.ArrayList(ConstantPoolInfo) {
        return self.constant_pool;
    }
};

pub const KlassRepo = struct {
    klass_lookup: std.StringHashMap(Klass),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) KlassRepo {
        return KlassRepo{
            .klass_lookup = std.StringHashMap(Klass).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *KlassRepo) void {
        var iterator = self.klass_lookup.valueIterator();
        while (iterator.next()) |klass| {
            klass.deinit(self.allocator);
        }
        self.klass_lookup.deinit();
    }

    pub fn addClass(self: *KlassRepo, name: []const u8, klass: Klass) !void {
        try self.klass_lookup.put(name, klass);
    }

    pub fn getKlass(self: *KlassRepo, name: []const u8) ?*Klass {
        return self.klass_lookup.getPtr(name);
    }

    pub fn initClasses(self: *KlassRepo, heap: *@import("heap.zig").Heap, debug: bool) !void {
        // todo, make this smarter
        var iterator = self.klass_lookup.valueIterator();
        while (iterator.next()) |klass| {
            var clinit_buffer: [256]u8 = undefined;
            const clinit = try std.fmt.bufPrint(&clinit_buffer, "<clinit>:()V", .{});
            if (klass.get_method(clinit)) |method| {
                const frame = try CallFrame.init(self.allocator, 0, 0, heap);
                defer frame.deinit();
                _ = try vm.execute(frame, klass.name, self, method.code, klass.constant_pool, debug);
            }
        }
    }
};
