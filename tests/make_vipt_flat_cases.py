"""New CPU cases for full-range direct loads; no game or firmware payload."""

from pathlib import Path
import json
import re
import subprocess
import sys
import tempfile


out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=False)
cases = []


def single_replace(text, old, new):
    assert text.count(old) == 1, (old, text.count(old))
    return text.replace(old, new)


with tempfile.TemporaryDirectory() as scratch:
    subprocess.run([sys.executable, "tests/make_vipt_segment_cpu.py", scratch],
                   check=True, stdout=subprocess.DEVNULL)
    templates = Path(scratch)
    for warm in ("cold", "warm"):
        for op in ("byte", "word", "dword", "zxbyte", "sxword"):
            src = templates / f"{warm}-{op}-aligned-valid.asm"
            body = src.read_text()
            body, n = re.subn(r"mov word \[pm_gdt\+40\],\d+",
                              "mov word [pm_gdt+40],65535", body, count=1)
            assert n == 1
            body = single_replace(body, "mov byte [pm_gdt+46],64",
                                  "mov byte [pm_gdt+46],207")
            label = f"flat-{warm}-{op}-valid"
            (out / f"{label}.asm").write_text(body)
            cases.append({"name": label, "expect": "data and direct admission"})

    # A full-range descriptor still faults if the last accessed byte wraps
    # beyond 4 GiB. Reuse the existing precise #GP fixture and change only
    # its descriptor and effective offset.
    for op, width in (("word", 2), ("dword", 4), ("sxword", 2)):
        src = templates / f"cold-{op}-aligned-cross.asm"
        body = src.read_text()
        body, n = re.subn(r"mov word \[pm_gdt\+40\],\d+",
                              "mov word [pm_gdt+40],65535", body, count=1)
        assert n == 1
        body = single_replace(body, "mov byte [pm_gdt+46],64",
                                  "mov byte [pm_gdt+46],207")
        body = single_replace(body, "mov esi,0x00000100",
                              f"mov esi,0x{0x100000000-width+1:08x}")
        label = f"flat-cold-{op}-overflow"
        (out / f"{label}.asm").write_text(body)
        cases.append({"name": label, "expect": "precise #GP; direct rejected"})

(out / "cases.json").write_text(json.dumps(cases, indent=2))
print(f"Generated {len(cases)} new flat-descriptor cases")
