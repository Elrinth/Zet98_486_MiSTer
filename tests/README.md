# CPU adapter simulation

The I/O adapter targets the native byte-address/length interface of MiSTer
ao486 commit `9d888c485bcf2e781824b303588668529a02015e`. It is not yet wired into
Zet98 and does not by itself deliver a faster core.

It retains PC-98's low/even and high/odd byte lanes, preserves aligned 16-bit
register accesses, and splits unaligned and 32-bit transfers. The peripheral
fabric must decode both selected lanes independently. The current Zet98 top
level's shared `ioaddr` expression requires attention before integration.
CPU and peripheral clocks are the same in this unit test; a clock-domain
bridge is still required for independent CPU and peripheral rates.

From the repository root in PowerShell:

```powershell
docker --context desktop-linux build -t zet98-sim -f tests/Dockerfile .
docker --context desktop-linux run --rm --network none --mount "type=bind,source=$($PWD.Path),target=/project,readonly" zet98-sim bash tests/run.sh
```

The bench checks byte, word and dword transfers at even/odd addresses,
16-bit port-address wrapping, correct peripheral byte-lane side effects,
wait-state stability, acknowledgement release and reset during a request.
The VHDL bench also compares OPNA/PIT enable rates and the VFO interrupt pulse
width at 20 and 40 MHz. These tests do not verify ao486 integration, BIOS boot,
complete peripheral timing, or Rusty performance.
