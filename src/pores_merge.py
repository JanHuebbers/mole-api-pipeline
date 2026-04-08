#!/usr/bin/env python3
import argparse
from pathlib import Path
import pandas as pd


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--inputs", nargs="+", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    dfs = []
    for p in args.inputs:
        p = Path(p)
        if not p.exists():
            continue
        dfs.append(pd.read_csv(p))

    # sort=False keeps column union without reordering alphabetically
    out = pd.concat(dfs, ignore_index=True, sort=False) if dfs else pd.DataFrame()

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(out_path, index=False)
    print(f"✅ merged {len(dfs)} files -> {out_path} ({len(out)} rows)")


if __name__ == "__main__":
    main()
