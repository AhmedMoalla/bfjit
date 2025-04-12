# JIT Compiler for Brainfuck

Ported from https://github.com/tsoding/bfjit for the purpose of learning Zig

## Quick Start
```console
$ zig build

$ # Run with JIT compiler (only available for x86_64 and aarch64)
$ ./zig-out/bin/bfjit src/tests/cases/Hello.b
$ # Or
$ zig build run -- src/tests/cases/Hello.b

$ # Run with interpreter
$ ./zig-out/bin/bfjit -i src/tests/cases/Hello.b
```

## TODO
- [ ] Compile brainfuck programs into executables
- [ ] Add option to output C
- [ ] Add option to output Java bytecode
- [ ] Make the memory grow automatically in JIT mode
- [ ] Add support for different cell sizes: 8, 16 or 32 bits (defaults to 8) in JIT mode