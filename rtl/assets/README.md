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
gray. This uses 330400 data bits instead of an eight-bit frame buffer.
The first frame lasts 80 ms and subsequent frames 40 ms, rounded to the next
video frame boundary. The caption is generated independently by the FPGA.

To regenerate from the supplied file, install Pillow and run:

```sh
python scripts/import_floppy_animation.py path/to/Amiga_disk_screens_30.gif
```
