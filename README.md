# JIT Compiler for Brainfuck

Ported from https://github.com/tsoding/bfjit for the purpose of learning Zig

## Quick Start
```console
$ zig build

$ # Run with JIT compiler
$ ./zig-out/bin/bfjit examples/hello.bf
$ # Or
$ zig build run -- examples/hello.bf

$ # Run with interpreter
$ ./zig-out/bin/bfjit --no-jit examples/hello.bf
```

## TODO
- [ ] Compile brainfuck programs into executables