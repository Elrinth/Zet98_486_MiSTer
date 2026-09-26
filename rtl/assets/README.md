# Disk activity animation

`floppy-animation.mem` contains the disk-only rectangle from the animation
provided by the project owner in the development conversation:

https://blogger.googleusercontent.com/img/b/R29vZ2xl/AVvXsEgTeU5X9xseDfNfLzypBFnRIOZmwix1P1Od8q8_lIOBZyybvO9po10VuWaKQ084rrU6MhxUTmFP5tkvsUUbE_DobOz26hNndEmdFju9o8aad7NIH-1JhbYtdTvUA2W9NpCOPzSIg8DqE4E/s1600/Amiga_disk_screens_30.gif

Source SHA-256: `7f2fbaf0bea12e76cee8396b0b7d926e1bf3a1c1c584279312fc6bd6873d8ceb`.
The original artist/license has not been identified; this development asset
must not be represented as original GPL-licensed artwork. Code licenses are
independent of the referenced artwork.

The importer retains all 59 frames, crops to the 50x56 disk, removes the
original caption and maps antialiasing colors to black, blue, pale pink and
gray. The canonical reference is 330400 bits. The FPGA reads a lossless 4x4
tile atlas: 495 shared tiles plus a 59-frame tile map use 112482 data bits.
An isolated Cyclone V fit uses 16 RAM blocks instead of 41 (25 fewer blocks).
All 165200 reference pixels are verified after packing. The partial rightmost
tile is padded with black, outside the visible 50-pixel disk.
The first frame lasts 80 ms and subsequent frames 40 ms, rounded to the next
video frame boundary. The caption is generated independently by the FPGA using `boot-font.mem`,
the same font as the core boot-help display. Palette index zero is transparent
in this overlay; the remaining three animation colors are unchanged.

To regenerate from the supplied file, install Pillow and run:

```sh
python scripts/import_floppy_animation.py path/to/Amiga_disk_screens_30.gif
```

To repack the existing canonical ROM without the GIF or Pillow:

```sh
python scripts/pack_floppy_animation.py
```
