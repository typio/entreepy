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

<!-- Time performance is quite good, memory is not optimal compared to other -->
<!-- solutions but still relatively nothing. The main time bottlenecks are the -->
<!-- heap allocations for file I/O. -->

I've developed a novel approach to decoding that utilizes a decode map. This map is keyed by the integer value of the code and stores a subarray of letters with matching code integer value - that is, the letters that correspond to codes with the same integer value - indexed by length minus one. For example, the map might include the following entries:

`{ 2: [_, a (10), e (010), ...], 5: [_, _, _, t (0101), ...] }.`

By utilizing this decode map, decoding can be performed much more quickly than by traversing a binary tree bit by bit. I haven't come across a faster decoding approach than this one.

#### Performance on MacBook Air M2, 8 GB RAM [@519f094](https://github.com/typio/entreepy/commit/519f094a3d04c15d1e34c9dad5af9095ceea4510)
| File | Original File Size | Compressed Size | Compression Time | Decompression Time |
| ---- | :----------------: | :-------------: | :--------------: | :----------------: |
| [Macbeth, Act V, Scene V](https://github.com/typio/entreepy/blob/main/res/nice.shakespeare.txt)   | 477 bytes | 374 bytes | 948μs | 2190μs |
| [A Midsummer Night's Dream](https://github.com/typio/entreepy/blob/main/res/a_midsummer_nights_dream.txt) | ~ 115 KB | ~ 66 KB | 21ms | 258ms |
| [The Complete Works of Shakespeare](https://ocw.mit.edu/ans7870/6/6.006/s08/lecturenotes/files/t8.shakespeare.txt) | ~ 5.5 MB | ~ 3.2 MB | 0.6s | 17s |

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
