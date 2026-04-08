# src/cxs_to_pdb.py
# Run inside ChimeraX:
#   ChimeraX-console.exe --nogui --script "<this.py> <session.cxs> <out_dir> [prefix] [n_models]" --exit

import os
import sys
from pathlib import Path
from chimerax.core.commands import run
from chimerax.atomic import AtomicStructure


def q(p: str) -> str:
    """
    Quote a path for ChimeraX command parsing.

    Important: ChimeraX command language treats backslash as an escape char,
    so for UNC paths (\\wsl.localhost\...) we must DOUBLE backslashes.
    """
    p = p.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{p}"'


def guess_prefix(session_stem: str) -> str:
    # e.g. 0097_02_1711_0ions_3hvmlo1didrct -> 0097_02_1711
    parts = session_stem.split("_")
    return "_".join(parts[:3]) if len(parts) >= 3 else session_stem


def id_tuple_to_spec(mid) -> str:
    # (1,) -> "#1", (1,2) -> "#1.2"
    return "#" + ".".join(str(x) for x in mid)


# ChimeraX provides a global "session"
sess = session  # noqa: F821

if len(sys.argv) < 3:
    raise SystemExit("Usage: cxs_to_pdb.py <session.cxs> <out_dir> [prefix] [n_models]")

session_file = sys.argv[1]
out_dir = sys.argv[2]
prefix = sys.argv[3] if len(sys.argv) >= 4 else guess_prefix(Path(session_file).stem)
n_models = int(sys.argv[4]) if len(sys.argv) >= 5 else None

os.makedirs(out_dir, exist_ok=True)

# Open the ChimeraX session
run(sess, f"open {q(session_file)}")

# Collect atomic structure models only (ignore maps, etc.)
models = [m for m in sess.models.list() if isinstance(m, AtomicStructure)]
models.sort(key=lambda m: m.id)

if not models:
    raise SystemExit("ERROR: No AtomicStructure models found after opening session.")

if n_models is not None:
    models = models[:n_models]

# Save each atomic model to its own PDB
for i, m in enumerate(models):
    spec = id_tuple_to_spec(m.id)
    out_pdb = os.path.join(out_dir, f"{prefix}_{i:02d}.pdb")
    run(sess, f"save {q(out_pdb)} models {spec}")

run(sess, "exit")
