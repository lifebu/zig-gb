# Next
## Test generator
- rename test2 to tst for shorter build name!
- Initialize allocating writer with capacity! (calculate it)!
- Reduce temp allocations in test_generator.zig
    - findRomFilesInPath()!!!
    - is bool_value a temp allcoation? 
- Combine test_generator.zig code snippets for code generation!
- Find a way to filter out specific tests that are incompatible with a specfic model.
    - Auto detect it by filename (different detection method per suite)?
    - model_detection enum for the detection method?
    - Maybe I can also manually set it for unit tests.
    - Also allow tests to run on all gb versio version
- Cleanup test category, filter and exclude.
    => Those should not be build commands for the test_generator!
- Make CoreType something that can be changed at runtime.
- Move from test2.zig to test.zig.
- remove old test_roms.test.zig.
- changes to the test_options seem to trigger a build of the test generator?
    => Only thing used by both is the definition of the test_category.

## Folder Structure
build/
    test_generator.zig
src/
    test.zig (generated).
    tests/
        *.test.zig => unit tests
        util/
            cpu_helper.zig: Move it here!
            rom_test_runtime.zig
test_data/
    roms/ (~4510).
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

# Docs
## Test generator
- Script that runs as a prerequisite build step before test
- Generates src/test.zig by using a unit test config and rom test config part of it's code (static).
- Generates for each test:
    - name, category filter, gb model for test.
- Filter out tests by category, test_filter, test_exclude and target gb model.

### Unit Tests
- Calls a run function. Based on a unit test config in code.
- Config: UnitTestConfig
    - filename, test-category, test_functions (generates a test per test function).

### Rom Tests
- Runner: util/rom_runner: actually runs the core and test parameters generated.
    - Inputs: core config, CoreType, exitConditionk passing, context.
- Config: RomTestConfig
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
