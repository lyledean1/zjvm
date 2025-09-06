// mock classes / methods
const std = @import("std");
const StackValue = @import("./stack.zig").StackValue;

const MockMethod = struct {
    name: []const u8,
    func: *const fn (args: []StackValue) void,
};

pub const MockObject = struct {
    class_name: []const u8,
    methods: []const MockMethod,

    pub fn invokeMethod(self: *const MockObject, method_name: []const u8, args: []StackValue) void {
        for (self.methods) |method| {
            if (std.mem.eql(u8, method.name, method_name)) {
                method.func(args);
                return;
            }
        }
        std.debug.print("Unknown method: {s} on class {s}\n", .{ method_name, self.class_name });
    }
};

fn printlnImpl(args: []StackValue) void {
    if (args.len > 0) {
        const arg = args[0];
        switch (arg.type) {
            .reference => {
                if (arg.value.reference != null) {
                    // todo : handle true pointer weirdness for "true"
                    const string_ptr = @as([*:0]const u8, @ptrCast(arg.value.reference.?));
                    std.debug.print("{s}\n", .{string_ptr});
                } else {
                    std.debug.print("null\n", .{});
                }
            },
            .int => {
                std.debug.print("{d}\n", .{arg.value.int});
            },
            .long => {
                std.debug.print("{d}\n", .{arg.value.long});
            },
            .float => {
                std.debug.print("{d}\n", .{arg.value.float});
            },
            .double => {
                std.debug.print("{d}\n", .{arg.value.double});
            },
            .return_address => {
                std.debug.print("return_address({d})\n", .{arg.value.return_address});
            },
        }
    }
}

fn stringBuilderAppendImpl(args: []StackValue) void {
    // Mock implementation - just print what's being appended
    if (args.len > 0) {
        const arg = args[0];
        switch (arg.type) {
            .int => {
                std.debug.print("{d}", .{arg.value.int});
            },
            .reference => {
                if (arg.value.reference != null) {
                    const string_ptr = @as([*:0]const u8, @ptrCast(arg.value.reference.?));
                    std.debug.print("{s}", .{string_ptr});
                } else {
                    std.debug.print("null", .{});
                }
            },
            else => {
                std.debug.print("[unknown]", .{});
            },
        }
    }
}

fn stringBuilderToStringImpl(args: []StackValue) void {
    _ = args;
}

const PRINT_STREAM_METHODS = [_]MockMethod{
    MockMethod{ .name = "println", .func = printlnImpl },
};

const STRINGBUILDER_METHODS = [_]MockMethod{
    MockMethod{ .name = "append", .func = stringBuilderAppendImpl },
    MockMethod{ .name = "toString", .func = stringBuilderToStringImpl },
};

pub const MockPrintStream = MockObject{
    .class_name = "java/io/PrintStream",
    .methods = &PRINT_STREAM_METHODS,
};

pub const MockStringBuilder = MockObject{
    .class_name = "java/lang/StringBuilder",
    .methods = &STRINGBUILDER_METHODS,
};
