#!/usr/bin/env python3
import argparse
import subprocess
from pathlib import Path
import sys

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--script", required=True, help="Path to the R script to run")
    ap.add_argument("--args", nargs="*", default=[], help="Arguments forwarded to the R script")
    a = ap.parse_args()

    script = Path(a.script)
    if not script.is_file():
        print(f"❌ R script not found: {script}", file=sys.stderr)
        return 2

    cmd = ["Rscript", "--vanilla", str(script)] + list(a.args)
    print("🔧 Running:", " ".join(cmd))
    return subprocess.run(cmd).returncode

if __name__ == "__main__":
    raise SystemExit(main())
