# JIT Compiler for Brainfuck

Ported from https://github.com/tsoding/bfjit for the purpose of learning Zig

## Quick Start
```console
$ zig build

$ # Run with JIT compiler (only available for x86_64 and aarch64)
$ ./zig-out/bin/bfjit examples/hello.bf
$ # Or
$ zig build run -- examples/hello.bf

$ # Run with interpreter
$ ./zig-out/bin/bfjit -i examples/hello.bf
```

## TODO
- [ ] Compile brainfuck programs into executables
- [ ] Add option to output C
- [ ] Add option to output Java bytecode
- [ ] Make the memory grow automatically in JIT mode