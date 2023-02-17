# entreepy

> ⚡ text compression

The name is binary trees + entropy coding.

### Usage

```bash
$ zig build && zig-out/bin/entreepy # path to file from cwd
```

Input file must be <1 terabyte.

### Compressed File Format

Introduces the `.et` file format, identified by the magic number `e7 c0 de`.

```bf
| magic number -> 3 bytes | length of dictionary - 1 (min length is 1) -> 1 byte |

| length of body -> 4 bytes |

| symbol -> 1 byte | symbol code length -> 1 byte | symbol code -> m bits | for n symbols

| packed big-endian bitstream of codes | starting on new byte

| some amount of end padding 0s -> <=3 bytes |
```
