#!/usr/bin/env python3
import argparse
import io
import json
import sys
from pathlib import Path
import zipfile

import pandas as pd


def _norm_zip_name(name: str) -> str:
    # report.zip entries are like "csv\path_1.csv" (Windows separators)
    return name.replace("\\", "/").lower()


def _find_member(zf: zipfile.ZipFile, want_endswith: str) -> str:
    """
    Find a member in the zip by case-insensitive normalized endswith match.
    Example want_endswith: "csv/path_1.csv"
    """
    want_endswith = want_endswith.lower()
    candidates = []
    for n in zf.namelist():
        nn = _norm_zip_name(n)
        if nn.endswith(want_endswith):
            candidates.append(n)

    if len(candidates) == 1:
        return candidates[0]
    if len(candidates) > 1:
        # Prefer the shortest / most direct path
        candidates.sort(key=lambda x: len(_norm_zip_name(x)))
        return candidates[0]

    # Fallback: sometimes zip may store without the "csv/" folder in front
    short = want_endswith.split("/", 1)[-1]
    for n in zf.namelist():
        nn = _norm_zip_name(n)
        if nn.endswith(short):
            return n

    raise FileNotFoundError(
        f"Could not find '{want_endswith}' inside report.zip. "
        f"Available CSVs: {[n for n in zf.namelist() if _norm_zip_name(n).endswith('.csv')]}"
    )


def _read_csv_from_zip(zf: zipfile.ZipFile, member: str) -> pd.DataFrame:
    raw = zf.read(member)
    # Let pandas sniff separators; MOLE is usually comma, but this is safer.
    # engine="python" allows sep=None (auto-detect).
    return pd.read_csv(io.BytesIO(raw), sep=None, engine="python")


def _atomic_write_csv(df: pd.DataFrame, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_path.with_suffix(out_path.suffix + ".tmp")
    df.to_csv(tmp, index=False)
    tmp.replace(out_path)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Extract MOLE Pores tables from report.zip into per-sample long CSVs."
    )
    ap.add_argument("--sample", required=True)
    ap.add_argument("--report-zip", required=True)
    ap.add_argument("--mole-ids", required=True)
    ap.add_argument("--out-pore", required=True)
    ap.add_argument("--out-physchem", required=True)
    args = ap.parse_args()

    sample = args.sample
    report_zip = Path(args.report_zip)
    mole_ids = Path(args.mole_ids)
    out_pore = Path(args.out_pore)
    out_phys = Path(args.out_physchem)

    if not report_zip.is_file():
        print(f"❌ report.zip not found: {report_zip}", file=sys.stderr)
        return 2
    if not mole_ids.is_file():
        print(f"❌ mole_ids.json not found: {mole_ids}", file=sys.stderr)
        return 2

    ids = json.loads(mole_ids.read_text(encoding="utf-8"))
    comp_id = ids.get("computationId", "")
    submit_id = ids.get("submitId", "")

    try:
        with zipfile.ZipFile(report_zip, "r") as zf:
            pore_member = _find_member(zf, "csv/path_1.csv")
            phys_member = _find_member(zf, "csv/path_1_physchem.csv")

            pore_df = _read_csv_from_zip(zf, pore_member)
            phys_df = _read_csv_from_zip(zf, phys_member)

        # Add provenance columns WITHOUT touching original headers/columns
        for df in (pore_df, phys_df):
            df.insert(0, "submitId", submit_id)
            df.insert(0, "computationId", comp_id)
            df.insert(0, "sample", sample)

        _atomic_write_csv(pore_df, out_pore)
        _atomic_write_csv(phys_df, out_phys)

        print(f"✅ wrote {out_pore}")
        print(f"✅ wrote {out_phys}")
        return 0

    except Exception as e:
        # Important: non-zero exit so Snakemake fails clearly
        print(f"❌ pores_extract failed for sample={sample}: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())