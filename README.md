# JIT Compiler for Brainfuck

Ported from https://github.com/tsoding/bfjit

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
- [ ] Add more examples from https://brainfuck.org/
- [ ] Run examples from build system (e.g. `zig build example hello`)
- [ ] Write tests to compare outputs with the outputs of this interpreter https://brainfuck.org/bcci.c
- [ ] Compile brainfuck programs into executables
- [ ] Optimize commons patterns (e.g. `[-]` sets the current cell to 0 by looping which can be reduced to a single instruction)