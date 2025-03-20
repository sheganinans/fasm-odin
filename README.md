# fasm-odin

Odin binding to the excellent fasm assembler.

Using the the latest v1.73 DLL version found [here](https://board.flatassembler.net/topic.php?t=6239).

Currently Windows only. This may change if/when fasm2 is stabilized and receieves a DLL version.

# Examples:

```sh
> odin run ./example/mul3

Using fasm version: 1.73

mul3(0) = 0
mul3(1) = 3
mul3(2) = 6
mul3(3) = 9
mul3(4) = 12
mul3(5) = 15
mul3(6) = 18
mul3(7) = 21
mul3(8) = 24
mul3(9) = 27
mul3(10) = 30

> odin run ./example/clockfreq
CPU frequency: 2445 MHz
```
