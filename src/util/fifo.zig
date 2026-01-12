const std = @import("std");
const assert = std.debug.assert;

/// Fifo interface on top of a statically allocated ringbuffer.
pub fn RingbufferFifo( comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        buffer: [capacity]T = undefined,
        read_index: usize = 0,
        write_index: usize = 0,

        /// Write slice. asserts capacity. 
        pub fn write(self: *Self, items: []const T) void {
            assert(self.length() + items.len <= self.buffer.len);

            for(items) |item| {
                self.writeItem(item);
            }
        }

        /// Write single item. asserts capacity. 
        pub fn writeItem(self: *Self, item: T) void {
            assert(self.length() + 1 <= self.buffer.len);

            self.buffer[self.mask(self.write_index)] = item;
            self.write_index = self.mask2(self.write_index + 1);
        }

        /// Write single item. Will not write of the fifo is full.
        pub fn writeItemDiscardWhenFull(self: *Self, item: T) void {
            if(self.length() + 1 > self.buffer.len) {
                return;
            }

            self.buffer[self.mask(self.write_index)] = item;
            self.write_index = self.mask2(self.write_index + 1);
        }

        /// Read single item. Removes it from FiFo
        pub fn readItem(self: *Self) ?T {
            if(self.isEmpty()) return null;

            const item_index: usize = self.mask(self.read_index);
            const item = self.buffer[item_index];
            self.buffer[item_index] = undefined;

            self.read_index = self.mask2(self.read_index + 1);
            return item;
        }

        /// Read single item. Does not remove it from FiFo
        pub fn peekItem(self: *Self) T {
            assert(!self.isEmpty());

            const item_index: usize = self.mask(self.read_index);
            return self.buffer[item_index];
        }

        /// Clear buffer
        pub fn clear(self: *Self) void {
            while(!self.isEmpty()) {
                _ = self.readItem();
            }
        }

        /// Clear buffer and realign indices to beginning of buffer.
        pub fn clearRealign(self: *Self) void {
            self.clear();
            self.write_index = 0;
            self.read_index = 0;
        }

        /// Returns if the underlying buffer is aligned. 
        /// This property is useful for functions that require to iterate over a contiguous memory region (sorting).
        pub fn isAligned(self: Self) bool {
            return self.read_index == 0;
        }

        /// Is the Fifo empty.
        pub fn isEmpty(self: Self) bool {
            return self.write_index == self.read_index;
        }
        
        /// How many elements the Fifo has.
        pub fn length(self: Self) usize {
            const wrap_offset = 2 * self.buffer.len * @intFromBool(self.write_index < self.read_index);
            const adjusted_write_index = self.write_index + wrap_offset;
            return adjusted_write_index - self.read_index;
        }

        fn mask(self: Self, index: usize) usize {
            return index % self.buffer.len;
        }

        fn mask2(self: Self, index: usize) usize {
            return index % (2 * self.buffer.len);
        }
    };
}
