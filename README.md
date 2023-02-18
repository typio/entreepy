# entreepy

> ⚡ Huffman file compression

The name is because binary trees + entropy coding.

### Usage

```bash
$ ./entreepy # path to file from cwd
```

Input file must be < 1 terabyte.

### Performance

Decoding is pretty efficient because it

### Compressed File Format

Introduces the `.et` file format, identified by the magic number `e7 c0 de`.

```bf
| magic number -> 3 bytes |
| (length of dictionary - 1) -> 1 byte |

| length of body -> 4 bytes |

| symbol -> 1 byte | for n symbols
| symbol code length -> 1 byte |
| symbol code -> m bits |

| packed big-endian bitstream of codes | starting on new byte

| end padding of 0's -> <=3 bytes |
```
