const std = @import("std");
const testing = std.testing;

/// Get the appropriate type of HashMap depending upon
/// the type of key to be stored
fn get_map_type(comptime T: type, comptime V: type) type {
    if (T == []const u8) {
        return std.StringHashMap(V);
    }

    return std.AutoHashMap(T, V);
}

/// A basic Directed Acyclic Graph, supports Topological Sorting based on
/// https://en.wikipedia.org/wiki/Topological_sorting#Depth-first_search
/// Node memory is managed by the caller, they will not be automatically
/// duplicated & freed by the `DAG`
pub fn DAG(comptime T: type) type {
    return struct {
        const Self = @This();

        const NodeMark = enum {
            Clear,
            Temporary,
            Permanent,
        };

        const TSortError = error{
            Cycle,
        };

        const ArrayType = std.ArrayList(T);

        /// Embed the metadata about NodeMark in the value itself
        /// to avoid having to create a new HashMap for performing
        /// Topological Sorting
        const ValType = struct {
            mark: NodeMark = .Clear,
            children: ArrayType,
        };

        const MapType = get_map_type(T, ValType);

        allocator: std.mem.Allocator,
        map: MapType,

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .allocator = alloc,
                .map = MapType.init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            var valIt = self.map.valueIterator();

            // Just deinit the array as we do not own the individual items
            // held by the array
            while (valIt.next()) |val| {
                val.children.deinit();
            }

            self.map.deinit();

            self.* = undefined;
        }

        fn get_or_put(self: *Self, node: T) !*ValType {
            // Make sure that we always get a pointer to the value
            // rather than the value directly, as the Array metadata
            // would get duplicated, causing inserted values to
            // not reflect in the Array stored in the HashMap
            if (self.map.getPtr(node)) |val| {
                return val;
            }

            try self.map.put(node, .{ .children = ArrayType.init(self.allocator) });
            return self.map.getPtr(node).?;
        }

        /// Creates an entry for the node (if non-existent) and adds
        /// `child` as one of it's children. Pass `null` as `child`
        /// if the `node` should exist in the graph but has no children
        pub fn add_child(self: *Self, node: T, child: ?T) !void {
            var val = try self.get_or_put(node);

            if (child) |passed_child| {
                try val.children.append(passed_child);
            }
        }

        fn tsort_inner(self: *Self, node: T, sorted: *std.ArrayList(T)) !void {
            var val = self.map.getPtr(node).?;

            switch (val.mark) {
                .Clear => {
                    val.mark = .Temporary;

                    for (val.children.items) |child| {
                        try self.tsort_inner(child, sorted);
                    }

                    val.mark = .Permanent;
                    try sorted.append(node);
                },
                .Temporary => {
                    // Cycle!
                    return TSortError.Cycle;
                },
                .Permanent => {
                    // Sorted
                    return;
                },
            }
        }

        /// Performs a Topological Sort on the `DAG`, starting from `root`
        /// Sorted values are stored in the `sorted` array provided by the
        /// caller
        pub fn tsort(self: *Self, root: T, sorted: *std.ArrayList(T)) !void {
            var valIt = self.map.valueIterator();

            while (valIt.next()) |val| {
                val.mark = .Clear;
            }

            try self.tsort_inner(root, sorted);
        }
    };
}

test "basic add functionality" {}
