
const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const DMA = @import("../dma.zig");
const mem_map = @import("../mem_map.zig");

pub fn runDMATest() !void {
    var dma: DMA.State = .{};

    const start_addr: u16 = mem_map.wram_low;
    var memory: [def.addr_space]u8 = [1]u8{0} ** def.addr_space;
    for(start_addr..(start_addr + 160), 0..) |addr, i| {
        memory[addr] = @truncate(i);
    }
    const start_write: u8 = @truncate(start_addr >> 8);

    // correct address calculation.
    var req: def.Request = .{ .address = mem_map.dma, .value = .{ .write = start_write } };
    DMA.request(&dma, &req);
    std.testing.expectEqual(true, dma.is_running) catch |err| {
        std.debug.print("Failed: DMA is triggered by a write request.\n", .{});
        return err;
    };
    std.testing.expectEqual(start_addr, dma.start_addr) catch |err| {
        std.debug.print("Failed: DMA start address is correct.\n", .{});
        return err;
    };
    std.testing.expectEqual(0, dma.offset) catch |err| {
        std.debug.print("Failed: DMA offset is set.\n", .{});
        return err;
    };
    std.testing.expectEqual(start_write, dma.dma) catch |err| {
        std.debug.print("Failed: DMA applied the memory request.\n", .{});
        return err;
    };

    // first 4 cycles nothing happens.
    req = .{};
    for(0..4) |_| {
        DMA.cycle(&dma, &req);
    }
    std.testing.expectEqual(false, req.isValid()) catch |err| {
        std.debug.print("Failed: For the first 4 cycles, the dma transfer does not start.\n", .{});
        return err;
    };

    // 2 cycle read, 2 cycle write. Includes DMA Bus conflict.
    for(0..160) |offset| {
        for(0..2) |_| {
            req = .{ .address = 0xFFF, .value = .{ .write = 0x00 } };
            DMA.cycle(&dma, &req);
        }
        std.testing.expectEqual(start_addr + offset, req.address) catch |err| {
            std.debug.print("Failed: DMA requests a read for offset {}.\n", .{ offset });
            return err;
        };
        const is_read = req.value == .read;
        std.testing.expectEqual(true, is_read) catch |err| {
            std.debug.print("Failed: DMA requests a read for offset {}.\n", .{ offset });
            return err;
        };
        const target_addr: usize = start_addr + offset;
        req.apply(&memory[target_addr]);

        for(0..2) |_| {
            req = .{ .address = 0xFFF, .value = .{ .write = 0x00 } };
            DMA.cycle(&dma, &req);
        }
        std.testing.expectEqual(mem_map.oam_low + offset, req.address) catch |err| {
            std.debug.print("Failed: DMA requests a write for offset {}.\n", .{ offset });
            return err;
        };
        const is_write = req.value == .write;
        std.testing.expectEqual(true, is_write) catch |err| {
            std.debug.print("Failed: DMA requests a write for offset {}.\n", .{ offset });
            return err;
        };
        std.testing.expectEqual(memory[target_addr], req.value.write) catch |err| {
            std.debug.print("Failed: DMA requests a write with correct value for offset {}.\n", .{ offset });
            return err;
        };
    }

    // dma is now done.
    std.testing.expectEqual(false, dma.is_running) catch |err| {
        std.debug.print("Failed: After transfer the dma must stop.\n", .{});
        return err;
    };
}
