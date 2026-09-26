"""Copy the unchanged, accepted B161 CPU into a local simulation fixture."""

from pathlib import Path
import hashlib
import sys


EXPECTED = "af28b02bf843fffb35d41fea3e5f21f9aa9a607cc4b6be55ce9b2137b841e1f1"
source = Path("rtl/vendor/z486/z486.sv").read_bytes()
assert hashlib.sha256(source).hexdigest() == EXPECTED
Path(sys.argv[1]).write_bytes(source)
