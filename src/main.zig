const std = @import("std");
const vm = @import("./runtime/vm.zig");
const RawClassFile = @import("./class/reader.zig").RawClassFile;
const builder = @import("./class/builder.zig");
const clz = @import("./runtime/klass.zig");
const Heap = @import("./runtime/heap.zig").Heap;
const CallFrame = @import("./runtime/stack.zig").CallFrame;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3 or args.len > 4) {
        std.debug.print("Usage: {s} <class directory> <main class name> [--debug]\n", .{args[0]});
        return;
    }

    var debug = false;
    if (args.len == 4 and std.mem.eql(u8, args[3], "--debug")) {
        debug = true;
    } else if (args.len == 4) {
        std.debug.print("Unknown flag: {s}\n", .{args[3]});
        return;
    }

    const class_dir_path = args[1];
    const main_class_name = args[2];

    var klass_repo = clz.KlassRepo.init(allocator);
    defer klass_repo.deinit();

    var heap = Heap.init(allocator);
    defer heap.deinit();

    // Load all .class files from the directory
    var class_dir = try std.fs.cwd().openDir(class_dir_path, .{ .iterate = true });
    defer class_dir.close();

    var dir_iterator = class_dir.iterate();

    while (try dir_iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".class")) {
            const file = try class_dir.openFile(entry.name, .{});
            defer file.close();

            var class_file = try RawClassFile.init(allocator);
            defer class_file.deinit();

            const buffered_reader = file.deprecatedReader();
            try class_file.parse(buffered_reader);

            const klass = try builder.buildKlass(allocator, &class_file);

            if (debug) {
                class_file.print();
            }

            try klass_repo.addClass(klass.name, klass);
        }
    }

    try klass_repo.initClasses(&heap, debug);

    const main_klass = klass_repo.getKlass(main_class_name).?;

    // Execute main method
    var main_buffer: [256]u8 = undefined;
    const main_fn = try std.fmt.bufPrint(&main_buffer, "main:([Ljava/lang/String;)V", .{});

    if (main_klass.get_method(main_fn)) |method| {
        const frame = try CallFrame.init(allocator, method.max_locals, method.max_stack, &heap);
        defer frame.deinit();
        _ = try vm.execute(frame, main_klass.name, &klass_repo, method.code, main_klass.get_constant_pool(), debug);
    } else {
        std.debug.print("Main method not found in class '{s}'\n", .{main_class_name});
    }
}
