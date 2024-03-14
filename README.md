entreepy<br/>
[![Actions Status](https://github.com/typio/entreepy/workflows/release/badge.svg)](https://github.com/typio/entreepy/actions)
====

> Text compression tool :zap:

The name is entropy coding + binary trees.

### Usage

![output](https://github.com/typio/entreepy/assets/26017543/75444090-547e-4c5b-a139-73918f22c789)

```
Entreepy - Text compression tool

Usage: entreepy [options] [command] [file] [command options]

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
    entreepy -ptd d text.txt.et -o decoded_text.txt
```

Input file must be < 1 terabyte. Be sure to use the same version of the program to decompress as compress.

### Performance

<!-- Time performance is good, memory is not optimal but still negligible. The main time bottlenecks are the heap allocations for file I/O. -->

I use a decode map which is keyed by the integer value of the code and stores a subarray of letters with matching code integer value - that is, the letters that correspond to codes with the same integer value - indexed by length minus one. For example, the map might include the following entries:

`{ 2: [_, a (10), e (010), ...], 13: [_, _, _, _, z (01101), ...] }.`

By utilizing this decode map, decoding can be performed much more quickly than by traversing a binary tree.

#### Performance on MacBook Air M2, 8 GB RAM - v1.0.0
| File | Original File Size | Compressed Size | Compression Time | Decompression Time |
| ---- | :----------------: | :-------------: | :--------------: | :----------------: |
| [Macbeth, Act V, Scene V](https://github.com/typio/entreepy/blob/main/res/nice.shakespeare.txt)   | 477 bytes | 374 bytes | 600μs | 3.2ms |
| [A Midsummer Night's Dream](https://github.com/typio/entreepy/blob/main/res/a_midsummer_nights_dream.txt) | ~ 112 KB | ~ 68 KB | 6.7ms | 262ms |
| [The Complete Works of Shakespeare](https://ocw.mit.edu/ans7870/6/6.006/s08/lecturenotes/files/t8.shakespeare.txt) | ~ 5.2 MB | ~ 3.0 MB | 111ms | 11.8s |

Next I'll add block based parallel decoding. After that I'm interested in exploring additional compression techniques; to support non-text file formats.

### Compressed File Format

Uses the `.et` file format, identified by the magic number `e7 c0 de`.

```bf
| magic number -> 3 bytes |
| file format version -> 1 byte |
| length of dictionary - 1 -> 1 byte |
| length of body -> 4 bytes |

for n symbols
| symbol -> 1 byte |
| symbol code length -> 1 byte |
| symbol code -> m bits |

| packed big-endian bitstream of codes | starting on new byte
```
