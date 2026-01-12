// TODO: Just some old code keeping for reference for now.
//
// test "blargg" {
//     const testRoms =  [_][]const u8{
//         "test_data/blargg_roms/cpu_instrs/individual/01-special.gb", 
//         // "test_data/blargg_roms/cpu_instrs/individual/02-interrupts.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/03-op sh,hl.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/04-op r,imm.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/05-op rp.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/06-ld r,r.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/07-jr,jp,call.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/08-misc instrs.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/09-op r,r.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/10-bit ops.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/11-op a,(hl).gb", 
//     }; 
//
//     const alloc = std.testing.allocator;
//
//     for (testRoms, 0..) |testRom, i| {
//         std.debug.print("{d}: Testing: {s}\n", .{i, testRom});
//         var cpu = try _cpu.CPU.init(alloc, testRom);
//         defer cpu.deinit();
//
//         var lastPC: u16 = 0;
//         while (lastPC != cpu.pc) {
//             lastPC = cpu.pc;
//             try cpu.frame();
//         }
//
//         const output: std.ArrayList(u8) = try blargg.parseOutput(&cpu, alloc);
//         defer output.deinit();
//
//         const passed: bool = blargg.hasPassed(&output);
//         if (!passed) {
//             std.debug.print("{s}\n", .{output.items});
//         }
//         try std.testing.expect(passed);
//     }
// }
//
//
//
// const std = @import("std");
//
// const CHAR_TABLE = [96]u8{
//     ' ', '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', 
//     '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?',
//     '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
//     'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_',
//     '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
//     'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~', ' ',
// };
//
// // TODO: These should be imported.
// const TILE_BASE_ADDRESS = 0x8000;
// const TILE_MAP_BASE_ADDRESS = 0x9800;
// const TILE_MAP_SIZE_X = 32;
// const TILE_MAP_SIZE_Y = 32;
// const TILE_SIZE_BYTE = 16;
//
// const WHITE_CHAR_BASE_ADDRESS = 0x8200;
// const BLACK_CHAR_BASE_ADDRESS = 0x8A00;
//
// pub fn parseOutput(memory: *const []8, alloc: std.mem.Allocator) !std.ArrayList(u8) {
//     std.debug.assert(memory.len == 0x10000);
//
//     var string = std.ArrayList(u8).init(alloc);
//     errdefer string.deinit();
//
//     var y: u16 = 0;
//     while (y < TILE_MAP_SIZE_Y) : (y += 1) {
//         var lineIsEmpty = true;
//         var line = try std.BoundedArray(u8, TILE_MAP_SIZE_X + 1).init(0);
//
//         var x: u16 = 0;
//         while (x < TILE_MAP_SIZE_X) : (x += 1) {
//             const tileMapAddress: u16 = TILE_MAP_BASE_ADDRESS + x + (y * TILE_MAP_SIZE_Y);
//             const tileAddressOffset: u16 align(1) = memory.*[tileMapAddress];
//             const tileAddress: u16 = TILE_BASE_ADDRESS + (tileAddressOffset * TILE_SIZE_BYTE);
//
//             const charBaseAddress: u16 = if (tileAddress >= BLACK_CHAR_BASE_ADDRESS) BLACK_CHAR_BASE_ADDRESS else WHITE_CHAR_BASE_ADDRESS;
//             const relativeIndex: u16 = (tileAddress - charBaseAddress) / TILE_SIZE_BYTE;
//
//             const char: u8 = CHAR_TABLE[relativeIndex];
//             if(lineIsEmpty and char != ' ') lineIsEmpty = false;
//             try line.append(char);
//         }
//         
//         if(lineIsEmpty) {
//             continue;
//         }
//
//         try line.append('\n');
//         for (line.slice()) |char| {
//             try string.append(char);
//         }
//     }
//
//     return string;
// }
//
// pub fn hasPassed(output: *const std.ArrayList(u8)) bool {
//     return std.mem.count(u8, output.*.items, "Passed") > 0;
// }
