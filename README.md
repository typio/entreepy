# entreepy
[![Actions Status](https://github.com/typio/entreepy/workflows/release/badge.svg)](https://github.com/typio/entreepy/actions)

> ⚡ Huffman compression

The name is because binary trees + entropy coding.

### Usage

```
$ entreepy [options] [command] [file] [command options]

Options:
    -h, --help     show help
    -p, --print    print decompressed text to stdout
    -t, --test     test/dry run, does not write to file
    -d, --debug    print huffman code dictionary and performance times to stdout

Commands:
    c    compress a file
    d    decompress a file

Command Options:
    -o, --output    output file (default: [file].et or decoded_[file])

Examples:
    entreepy -d c text.txt -o text.txt.et
    entreepy -ptd d text.txt.et
```

Input file must be < 1 terabyte. I recommend keeping an uncompressed backup or testing the program's
decompression before deleting the original, the program hasn't been robustly tested. Be sure to use
the same version of the program to decompress as compress.

### Performance

<!-- Time performance is quite good, memory is not optimal compared to other -->
<!-- solutions but still relatively nothing. The main time bottlenecks are the -->
<!-- heap allocations for file I/O. -->

I've developed a novel approach to decoding that utilizes a decode map. This map is keyed by the integer value of the code and stores a subarray of letters with matching code integer value - that is, the letters that correspond to codes with the same integer value - indexed by length minus one. For example, the map might include the following entries:

`{ 2: [_, a (10), e (010), ...], 5: [_, _, _, t (0101), ...] }.`

By utilizing this decode map, decoding can be performed much more quickly than by traversing a binary tree bit by bit. I haven't come across a faster decoding approach than this one.

#### Current Performance on MacBook Air M2, 8 GB RAM
| File | Original File Size | Compressed Size | Compression Time | Decompression Time |
| ---- | :----------------: | :-------------: | :--------------: | :----------------: |
| [Macbeth, Act V, Scene V](https://github.com/typio/entreepy/blob/main/res/nice.shakespeare.txt)   | 477 bytes | 374 bytes | 240μs | 950μs |
| [A Midsummer Night's Dream](https://github.com/typio/entreepy/blob/main/res/a_midsummer_nights_dream.txt) | ~ 115 KB | ~ 66 KB | 2.2ms | 150ms |
| [The Complete Works of Shakespeare](https://ocw.mit.edu/ans7870/6/6.006/s08/lecturenotes/files/t8.shakespeare.txt) | ~ 5.5 MB | ~ 3.2 MB | 0.1s | 7s |

### Compressed File Format (tentative)

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
