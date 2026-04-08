# src/run_cxs_to_pdb.py
# Run in WSL:
#   python src/run_cxs_to_pdb.py .cxs/<session>.cxs data [prefix] [n_models]

import os
import sys
import subprocess
from pathlib import Path

import yaml


def load_chimerax_path(cfg_path: Path) -> str:
    if not cfg_path.is_file():
        raise FileNotFoundError(f"Config not found: {cfg_path}")
    with cfg_path.open("r") as f:
        cfg = yaml.safe_load(f) or {}
    chx = cfg.get("chimerax_path")
    if not chx:
        raise ValueError(f"'chimerax_path' missing in {cfg_path}")
    if not Path(chx).exists():
        raise FileNotFoundError(f"ChimeraX exe not found at: {chx}")
    return chx


def wsl_to_win(p: Path) -> str:
    # Convert a WSL path to Windows path / UNC via wslpath
    out = subprocess.check_output(["wslpath", "-w", str(p)], text=True).strip()
    return out


def main():
    if len(sys.argv) < 3:
        raise SystemExit("Usage: run_cxs_to_pdb.py <session.cxs> <out_dir> [prefix] [n_models]")

    session_cxs = Path(sys.argv[1]).resolve()
    out_dir = Path(sys.argv[2]).resolve()
    prefix = sys.argv[3] if len(sys.argv) >= 4 else None
    n_models = sys.argv[4] if len(sys.argv) >= 5 else None

    # Repo root assumed: src/ is one level below
    repo_root = Path(__file__).resolve().parents[1]
    cfg_path = repo_root / "cxs" / "chimeraX_path.yml"
    chx_exe = load_chimerax_path(cfg_path)

    chx_script = (repo_root / "src" / "cxs_to_pdb.py").resolve()
    if not chx_script.is_file():
        raise FileNotFoundError(f"ChimeraX script not found: {chx_script}")

    if not session_cxs.is_file():
        raise FileNotFoundError(f"Session not found: {session_cxs}")

    out_dir.mkdir(parents=True, exist_ok=True)

    win_py = wsl_to_win(chx_script)
    win_cxs = wsl_to_win(session_cxs)
    win_out = wsl_to_win(out_dir)

    # ChimeraX expects: --script "<py> <args...>"
    parts = [win_py, win_cxs, win_out]
    if prefix:
        parts.append(prefix)
    if n_models:
        # if prefix omitted but n_models provided, require prefix position:
        if not prefix:
            # keep argv positions consistent for cxs_to_pdb.py
            parts.append("")  # prefix = ""
        parts.append(str(n_models))

    script_arg = " ".join(f"\"{p}\"" for p in parts)

    cmd = [chx_exe, "--nogui", "--script", script_arg, "--exit"]

    print("Running:", " ".join(cmd))
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace")
    out, err = proc.communicate()

    if out.strip():
        print("=== ChimeraX stdout ===")
        print(out)
    if err.strip():
        print("=== ChimeraX stderr ===")
        print(err)

    if proc.returncode != 0:
        raise SystemExit(proc.returncode)


if __name__ == "__main__":
    main()
