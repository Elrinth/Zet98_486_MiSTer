# OpenBIOS floppy media events

The core provides an optional media-change latch at byte I/O port **7ED0h**.
It lets OpenBIOS notify DOS of real mount/eject transitions without issuing
commands to the uPD765 inside its interrupt handler. It is disabled on reset,
so an older BIOS retains the previous core behavior.

Read bits:

- 7–4: `Ah`, identifying version 1 of this register.
- 3: notification enable.
- 2: existing floppy IRQ (controller or shared VFO timer).
- 1–0: sticky media-change bits for floppy units 1 and 0.

Writes:

- `A5h`: enable and discard pre-enable events.
- `00h`: disable.
- `80h | drive_mask`: acknowledge the indicated pending drive bits.

The latch observes `diskemu_mister`'s validated media-present signals. Replacing
an image drops presence while it reloads, including replacement by another image
of the same size. Either edge records a change. Multiple changes before service
coalesce: the BIOS needs to invalidate cached media state, not count swaps.
A transition on an acknowledgement clock wins over the acknowledgement.

Pending notifications wait for the controller to become idle. Existing floppy
IRQs have priority. A clock of low IRQ is preserved after existing IRQs and after
acknowledgements so another pending event produces an edge at the 8259. The
extension shares the selected interface's IRQ10/IRQ11 routing.

OpenBIOS opts in during cold POST only after checking the signature. Its IRQ
handler records a not-ready/change status for the affected unit before returning
to a chained DOS handler: 0564h + 8×unit on the 1 MB interface, or 05D8h + 2×unit
on the 640 KB interface. This invalidates cached floppy information. Media-only
IRQs do not set the BIOS's seek/data completion flags; concurrent native IRQs
still do. Existing command-result bytes and FDC result phases are preserved.

This feature requires the matching core and OpenBIOS. Older cores return FFh at
this port; the BIOS retains its legacy IRQ behavior there. It is not a full
implementation of uPD765 asynchronous ready polling for third-party BIOSes.

OpenBIOS also validates the active interface against port BEh before accepting
INT 1Bh requests. A probe must not switch the controller or advertise a second
bank of drives. POST and floppy boot select an interface explicitly; 2DD boot
remains supported.

Validation:

- `tests/run-floppy-events.sh`: disabled legacy behavior, real transitions,
  busy/native-IRQ deferral, IRQ edge re-arming, per-drive acknowledgements,
  simultaneous transition/acknowledgement, reset.
- OpenBIOS `tests/test_floppy_events.py`: interface probes without side effects,
  explicit interface selection, both DOS interrupt chains, media-only versus
  concurrent native completion, register preservation, and old-core fallback.
- OpenBIOS's existing floppy, DMA, DOS boot, POST, graphics and BASIC suites.

Hardware qualification is recorded in `SWORD_DANCER_FLOPPY_DEBUG.md`.
