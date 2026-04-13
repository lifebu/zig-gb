# Next
## Test generator
- A generator script that is run as a prerequisite build step before test
    - Does zig always run this step? or only when needed?
- It generates src/test.zig by scanning src/test/*.test.zig files.
    - Should *.test.zig have a specific structure? Like specific functions to call?
- What it needs to generate:
    - The name of the test:
        - Should include: system, test_suite, file_name
    - which category this test belongs to:
    - which model this test is for: All, DMG, GBC, etc.
- What to generate:
    - test.zig files: unit tests
        - one function called run (that runs the test).
        - test name is the file name.
        - Which category it applies to is defined by a unit test config
    - test roms:
        - use the test_config.zog in the roms folder to generate these.
        - Similar to test_roms.test.zig: TestRomConfig
- test_rom.test.zig:
    - Generation: For each test file it creates a emulator core config, CoreType (from a determined set of core combinations), and additional data (see: RomTestConfig)
    - Execution Framework: Running test and core, exitCondition, passing and context => rom_test_runtime.zig.
- Two elements:
    - Actual generation logic.
    - Configuration to add/remove tests (.zon file?)
- Running the generator:
    - Should it be compiled or just imported by the build script?
    - Should the test generator always be run before the test step? How long does it take?
        - Maybe this invalidates the caching that zig does and every time the tests run, they need to recompile even when the test.zig file has not changed?

### Unit Test Config
- File: one *.test.zig file.
- Test category.

### Rom Test Config
- Files:
    - path: Either a file or a directory.
    - filter_files: some files to exclude.
- Test:
    - Category.
- Core:
    - Bootrom or not? (default no).
- Subsystem:
    - Which subsystems are getting tested by this.
    - If a subsystem is not needed it will use a void version.
- Model:
    - DMG, CGB, SGB, Any
    - Filename: Auto detect revision from filename
    - Do I need the exact dmg cpu revisions?
- Exit Condition:
    - none, blargg (test parsing), breakpoint (ld b,b), timeout (where the timout is not an error).
- Timeout:
    - maximum number of time units until the test is abborted
    - cycles, frames, seconds, sec
- Pass/Fail:
    - fibonacci: On Success: B = 3, C = 5, D = 8, E = 13, H = 21, L = 34
    - mbc3: contains an f (for failure) in the PPU output.
    - memory location.
    - text: text on screen.
- Context:
    Gives you more information if you fail.
    - none
    - memory location.
    - text parsing: blargg, mooneye, mbc3, bully and gambatte print on the screen.

## Folder Structure
src/
    test.zig (generated).
    tests/
        test_config.zon: Used by the test generator for unit tests in src/tests/*.test.zig
        *.test.zig => unit tests
        util/
            cpu_helper.zig: Move it here!
            rom_test_runtime.zig
test_data/
    roms/
        test_config.zon: Used by the test genenerator for rom tests.
        readme.md: has links to the sources (with version!), methodologies, compilation, etc.
        suite/ (mooneye, etc)
            suite.md: original md file from source.
            compilation_file (make or sth).
            **content**: Can be as many sub folders as the use.
                - test.gb, test.asm (source code).
    single_step_tests/
        readme.md: has links to the sources, methodologies, compilation, etc.

### Managing test-files
- Source: https://github.com/c-sp/game-boy-test-roms
N- Build from source:
    - Either use wla-dx (https://github.com/vhelin/wla-dx) or rgbds (https://github.com/gbdev/rgbds)
        - wla-dx: 3 (blargg), (gbmicro), (mooneye)
        - rgbds: 13
        - custom: 1 (gambatte)
    => To much work right now => Embedd binaries + source file.

## Custom test runner
- multithreaded (zig 0.16) using io.async().
- CLI:
    custom:
    only_categories (comma-seperated)
    exclude_tests (comma-seperated)
    filter_tests (comma-seperated)
    gameboy_model (dmg, mgb, gbc, etc)
    seed
    break_on_fail (default: no)
    
    from build server:
    --listen=-
    --seed=
    --cache-dir=
- Should support simple and server mode.
    - simple might be required for high performance?
- Output:
    - Should give me some statistics of passed/failed tests per category and test-suite.
    - Failed tests could also include:
        - Links to the assembly source file.
- Links:
    - How to write a basic test runner: https://www.youtube.com/watch?v=jpY6VHsHsWU
    - https://codeberg.org/ziglang/zig/src/branch/master/lib/compiler/test_runner.zig
    - Example test runner: https://github.com/dokwork/zrunner
    - Another (complicated) test runner: https://github.com/oneopane/test-runner




# Later
## Test imports and modules
- It would be nice to have the tests in it's own project / module.
- so you have src/ and test/ in root folder.
=> How do other projects handle this?

## APU tests
- blargg apu tests
- samesuite apu tests (requires some gbc features).
    - Speed switch
    - PCM Register: 2 Bytes that contain the 4 channels digital output (nibbles).
- gambatte sound tests.
- APU tests: I need to implement some GBC functions.

## PPU Output
- ppu tests could use static images (no cpu is running) or dynamic images (CPU changes PPU state).
- palette: #00_00_00, #55_55_55, #AA_AA_AA, #FF_FF_FF

### color-id conversion
- conversion: png =rgbgfx> 2bpp => color_id array
- do conversion with a tool that can be run as a build step (like shdc).
- automated tests load the prepared file and compare it with result and create a diff image.
- show the results in a new window: imgui table with:
    - columns: expected, got, diff
    - rows: a specific test.
- It would be neat to use the zig test web-ui.

### load at runtime:
- Use stb_image? https://github.com/nothings/stb, https://github.com/zig-gamedev/zstbi
- load the file and convert it to binary data pixels with stb_image.
- Example: https://github.com/floooh/sokol-samples/blob/master/sapp/loadpng-sapp.c

## Generate rom-blob
- The test_roms test needs to load all of the .gb files individually.
    => Generate one blob file with a header? (~61MByte).
- The test generator would create this blob.
- The test runner would load it and pass it to the test functions (?).
    - The specific rom test would then get a slice of that memory (?).

## Initial Value tests
https://gbdev.io/pandocs/Power_Up_Sequence.html
- Has some tables for initial values of the system after boot up sequence.
- This could be a good test at some point.
