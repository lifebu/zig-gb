
const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const MMU = @import("../mmu.zig");
const def = @import("../defines.zig");
const DMA = @import("../dma.zig");
const mem_map = @import("../mem_map.zig");

pub fn runDMATest() !void {
    var dma: DMA.State = .{};
    var mmu: MMU.State = .{}; 

    // Initialize with test memory.
    for(0x0300..0x039F, 1..) |addr, i| {
        mmu.memory[@intCast(addr)] = @truncate(i);
    }
    for(mem_map.oam_low..mem_map.oam_high + 1) |addr| {
        mmu.memory[@intCast(addr)] = 0;
    }

    // correct address calculation.
    var request_data: u8 = 0x03;
    mmu.request.write = mem_map.dma;
    mmu.request.data = &request_data;
    DMA.cycle(&dma, &mmu);
    std.testing.expectEqual(true, dma.is_running) catch |err| {
        std.debug.print("Failed: DMA is triggered by a write request.\n", .{});
        return err;
    };
    std.testing.expectEqual(0x0300, dma.start_addr) catch |err| {
        std.debug.print("Failed: DMA start address is correct.\n", .{});
        return err;
    };
    std.testing.expectEqual(0, dma.offset) catch |err| {
        std.debug.print("Failed: DMA offset is set.\n", .{});
        return err;
    };
    std.testing.expectEqual(0x03, mmu.memory[mem_map.dma]) catch |err| {
        std.debug.print("Failed: DMA applied the memory request.\n", .{});
        return err;
    };

    // first 4 cycles nothing happens.
    for(0..4) |_| {
        DMA.cycle(&dma, &mmu);
    }
    std.testing.expectEqual(0, mmu.memory[mem_map.oam_low]) catch |err| {
        std.debug.print("Failed: For the first 4 cycles, the dma transfer does not start.\n", .{});
        return err;
    };

    // every 4 cycles one byte is copied.
    //const oam_size = mem_map.oam_high - mem_map.oam_low;
    for(0..160) |byte_idx| {
        for(0..def.t_cycles_per_m_cycle) |_| {
            DMA.cycle(&dma, &mmu);
        }
        std.testing.expectEqual(mmu.memory[mem_map.oam_low + byte_idx], mmu.memory[dma.start_addr + byte_idx]) catch |err| {
            std.debug.print("Failed: DMA copies the correct value to oam.\n", .{});
            return err;
        };
        std.testing.expectEqual(0, mmu.memory[@intCast(mem_map.oam_low + byte_idx + 1)]) catch |err| {
            std.debug.print("Failed: DMA copies only one byte and not the next one.\n", .{});
            return err;
        };
    }

    // dma is now done.
    std.testing.expectEqual(false, dma.is_running) catch |err| {
        std.debug.print("Failed: After transfer the dma must stop.\n", .{});
        return err;
    };

    // TODO: Also test DMA bus conflicts and what the CPU/PPU could access.
    // https://hacktix.github.io/GBEDG/dma/
    // https://gbdev.io/pandocs/OAM_DMA_Transfer.html
}
