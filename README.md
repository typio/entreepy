# entreepy

> ⚡ Huffman compression

The name is because binary trees + entropy coding.

### Usage

Project is nearly fully functional, and will have release binaries
after these are done

- [ ] CLI is added
- [ ] Bugs with large files are resolved
- [ ] Code is cleaned up

```bash
$ ./entreepy # path to file from cwd
```

Input file must be < 1 terabyte.

### Performance

Time performance is quite good, memory is not optimal compared to other
solutions but still relatively nothing. The main time bottlenecks are the
heap allocations for file I/O.

I believe the process for decoding is slightly original because I have a decode
table indexed by the integer value of the code which stores a subarray of
matching symbols indexed by length. This allows for approaches to decoding much
faster than traversing a binary tree in single bits. I haven't seen a faster
approach to decoding than this one.

### Compressed File Format

Introduces the `.et` file format, identified by the magic number `e7 c0 de`.

```bf
| magic number -> 3 bytes |
| (length of dictionary - 1) -> 1 byte |

| length of body -> 4 bytes |

for n symbols
| symbol -> 1 byte |
| symbol code length -> 1 byte |
| symbol code -> m bits |

| packed big-endian bitstream of codes | starting on new byte

| 0 padding -> <=3 bytes |
```
