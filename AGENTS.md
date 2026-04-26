# Agents.md - Guidelines for Agentic Coding in zig-gb

This document provides build commands, testing instructions, and code style guidelines for agents operating in the zig-gb (Game Boy emulator) repository.

## Build Commands

### Standard Build
```bash
zig build
```

### Run the Application
```bash
zig build run
```

### Run with Custom ROM
```bash
zig build run -- <path-to-rom.gb>
```

### Run with Specific Plugin Model
```bash
zig build run -Dppu_plugin=cycle -Dapu_plugin=cycle
# Or: -Dppu_plugin=void|frame|runtime, -Dapu_plugin=void|runtime
```

### Build Options
- `-Dppu_plugin`: `runtime`, `void`, `frame`, or `cycle` (default: `runtime`)
- `-Dapu_plugin`: `runtime`, `void`, or `cycle` (default: `runtime`)
- `-Denable_audio`: `true` or `false` (default: `true` in Release/asan modes)
- `-Dtracy`: Enable Tracy profiler (default: `true`)

## Testing Commands

### Run All Tests
```bash
zig build test
```

### Run Test Generator
```bash
zig build test_generator
```
Note: The test generator creates test files from `.gb` ROMs in the `tests/` directory. Run this before running tests when adding new test ROMs.

### Run Single Test Category
```bash
zig build test -Dtest_category=cart   # cart, instr, cpu, memory, mmio, ppu, apu
```

### Run Specific Test by Name
```bash
zig build test -Dtest_filter=tma_write_reload
```
Note: Do not include the `.gb` extension.

### Exclude Specific Tests by Name
```bash
zig build test -Dtest_exclude=tma_write_reload
# Or multiple tests separated by commas:
zig build test -Dtest_exclude=tma_write_reload,tima_write_reloading
```
Note: Do not include the `.gb` extension.

### Available Test Categories
- `all` (default), `cart`, `instr`, `cpu`, `memory`, `mmio`, `ppu`, `apu`

## Code Style Guidelines

Follow conventions in `doc/zig_style.zig` and established patterns in the codebase.

### Import Order
1. Standard library: `const std = @import("std");`
2. Build options: `const build_options = @import("build_options");`
3. External libraries: `const sokol = @import("sokol");`
4. Internal modules: `const APU = @import("apu.zig");`

### File Organization (Order)
1. Constants and Definitions
2. Types
3. Functions: init/deinit -> Core -> Helper (Alphabetically)

### Naming Conventions
- **Constants**: `SCREAMING_SNAKE_CASE`
- **Types/Structs/Enums**: `PascalCase`
- **Functions**: `camelCase`
- **Variables/Fields**: `snake_case`

### Type Annotations
Explicit types required for function parameters and return types. Avoid redundant annotations when type can be inferred.

### Packed Structs
Use for tight memory alignment (e.g., hardware register emulation).

### Error Handling
- Use `!void` and `error.SkipZigTest` for conditional tests
- Prefer `catch unreachable` for impossible errors
- Use `try` for recoverable errors

### Memory Management
Always use `defer`/`errdefer` for cleanup.

### Enum vs Comptime
- Use `enum` for runtime values
- Use `comptime` for compile-time choices

### Documentation
Document public APIs and constants that affect behavior.

### Common Pitfalls
1. **Memory leaks**: Always use `errdefer`/`defer` for cleanup
2. **Uninitialized memory**: Initialize variables explicitly, `var x: i32 = undefined;`
3. **Wrong integer sizes**: Use explicit sizes (`u8`, `u16`, `i32`) for hardware registers
4. **Optionals**: Check for null with `if (opt) |val|` pattern
5. **Slices vs arrays**: Use `[]u8` for runtime-known sizes, `[N]u8` for fixed

### Useful Development Commands
```bash
zig build -Dverbose=true  # Analyze build
```

## Project Structure
```
src/
├── main.zig             # Application entry
├── test.zig             # Test entry
├── test_runner.zig      # Custom test runner
├── test_generator.zig   # Test generator (creates tests from ROMs)
├── cpu.zig               # CPU: instructions, registers, interrupts, halt
├── ppu.zig               # PPU: pixel rendering, LCD, sprites, palettes
├── apu.zig               # APU: audio channels, wave, noise, envelope
├── memory.zig            # Memory: boot rom, RAM, dma controller
├── cart.zig              # Cartridge: cart-rom, cart-ram, mbc
├── mmio.zig              # MMIO: timer, divider, serial, joypad
├── core.zig              # Core emulator loop
├── config.zig            # Configuration
├── platform.zig          # Platform (sokol/app)
├── defines.zig           # Shared definitions
├── tests/*.test.zig      # Test files
└── shaders/*.glsl        # Graphics shaders
```

## External Dependencies
- **sokol**: Graphics/audio/inputs
- **cimgui**: Debug UI
- **tracy**: Profiler

## Additional Notes
- Minimum Zig version: 0.15.2 (see `build.zig.zon`)
- Uses custom build system in `build.zig` (not standard `build.zig.zon`)
- Tests filtered by category at build time, not runtime
- Test generator runs automatically with `zig build test` to generate tests from ROMs
- Tracy can be disabled with `-Dtracy=false` for faster builds

## Important Notes
- Do NOT run `zig fmt src/` - it creates too much noise in diffs
