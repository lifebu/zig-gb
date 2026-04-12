# TODO
- Changing which tests to run needs a recompile.
    - Maybe I have a build step that scans the folders for test roms and generates a test rom zig file that includes all roms as test?
    - It gives the test the input of the generated data?
    - I can run this rarely, when needed?
- I currently break at the first failing test.
    - Run all test roms and see how many break.
    => This is because I don't have a test per file :/
- I am missing the source code + binary files for testing in the repository.
    - Create a better folder structure for this. 
- Better performance plz
    - Each single file should be a test in the end!
    - Run tests in parallel.
- APU tests: I need to implement some GBC functions.
- Gameboy model filtering.

# Test suite
- run all test roms that test a certain system automatically.
- can filter for specific tests.
- have one config table in code defining which tests to run.

## Config
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
    - cycles, seconds, sec
- Pass/Fail:
    - fibonacci: On Success: B = 3, C = 5, D = 8, E = 13, H = 21, L = 34
    - memory location.
    - text: text on screen.
- Context:
    Gives you more information if you fail.
    - memory location.
    - text parsing: blargg, mooneye and gambatte print on the screen.

## MT
- once zig has reached 0.16, try to use multiple threads for the test_roms runner.
- use std.io.Threaded and enqueue tasks with io.async()

# PPU Output
- ppu tests could use static images (no cpu is running) or dynamic images (CPU changes PPU state).
- palette: #00_00_00, #55_55_55, #AA_AA_AA, #FF_FF_FF

## color-id conversion
- conversion: png =rgbgfx> 2bpp => color_id array
- do conversion with a tool that can be run as a build step (like shdc).
- automated tests load the prepared file and compare it with result and create a diff image.
- show the results in a new window: imgui table with:
    - columns: expected, got, diff
    - rows: a specific test.
- It would be neat to use the zig test web-ui.

## load at runtime:
- Use stb_image? https://github.com/nothings/stb, https://github.com/zig-gamedev/zstbi
- load the file and convert it to binary data pixels with stb_image.
- Example: https://github.com/floooh/sokol-samples/blob/master/sapp/loadpng-sapp.c

# Managing test-files
- Source: https://github.com/c-sp/game-boy-test-roms
N- Build from source:
    - Either use wla-dx (https://github.com/vhelin/wla-dx) or rgbds (https://github.com/gbdev/rgbds)
        - wla-dx: 3 (blargg), (gbmicro), (mooneye)
        - rgbds: 13
        - custom: 1 (gambatte)
    - If I ever do this, then convert every test rom from wla-dx to rgbds.
    - Because I already want rgbgfx to convert expected images to a binary format.
    => I think this is just to much work right.
- Embed binaries in repository:
    - Easiest to do and allows some additional generated test data in those folders.
    - Maybe some note which version was downloaded (git tag?)

# custom test runner
- Use a custom multithreaded test-runner with zig 0.16 io?
- a MT testrunner would especially be nice if I also use a test generator with it.
    => Each test rom that I actually want to run generates it's own unique unit test.
    => I am generting the overarching test.zig file as a build step before compiling the tests.
    => My Testrunner then runs them multithreaded.
    => This automatically gives me statistics, as the test names are generated from the test suites (blargg) and file names!
- I want to have a statistics for the different test suites how much i am currently passing.

# Initial Value tests
https://gbdev.io/pandocs/Power_Up_Sequence.html
- Has some tables for initial values of the system after boot up sequence.
- This could be a good test at some point.

# Test Generator.
- the above points could mean that it makes more sense to have a test generator zig script that I run once.
- It preprocesses data so that the tasks can be faster and do certain steps better?

## Managing zig-tests
- It would be neat to have a more detailed pass/success rate and run every single test instead of only the first one that fails?
- I could also generate some tests at compile time to be run.
    - go through every x.test.zig file and find tests and generate a top-level test.zig file?
    - can also use some custom code for this. It can also generate a test for each test rom test file.
    - test name must be a compile time string: https://ziggit.dev/t/generating-tests-at-comptime/6473
    - Or like the ziggit above I use one comptime block in test.zig that generates the individual tests for me?

## Generate rom-blob
- The test_roms test needs to load all of the .gb files individually.
- Would it make sense to generate one blob file with all roms inside with a header?
- Just load this file once?
- How can I detect file changes and only run the test generator once?

# Audio tests:
- blargg apu tests
- samesuite apu tests (requires some gbc features).
- gambatte sound tests.
