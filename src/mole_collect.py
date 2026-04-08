#!/usr/bin/env python3
import argparse
import json
import time
from pathlib import Path

import requests


def get_compinfo(api_base: str, computation_id: str) -> dict:
    url = f"{api_base.rstrip('/')}/CompInfo/{computation_id}"
    r = requests.get(url, timeout=60)
    r.raise_for_status()
    return r.json()


def list_submit_ids(compinfo: dict) -> list[str]:
    subs = compinfo.get("Submissions", []) or []
    out = []
    for s in subs:
        sid = s.get("SubmitId")
        if sid is None:
            continue
        out.append(str(sid))
    return out


def pick_submit_id(compinfo: dict, preferred: str | None = None) -> str:
    submit_ids = list_submit_ids(compinfo)
    if not submit_ids:
        raise RuntimeError(f"No submissions listed in CompInfo: {compinfo}")

    if preferred and preferred in submit_ids:
        return preferred

    def sid_key(x: str) -> int:
        try:
            return int(x)
        except Exception:
            return -1

    return sorted(submit_ids, key=sid_key)[-1]


def status(api_base: str, computation_id: str, submit_id: str) -> dict:
    url = f"{api_base.rstrip('/')}/Status/{computation_id}"
    r = requests.get(url, params={"submitId": submit_id}, timeout=60)
    r.raise_for_status()
    return r.json()


def is_submitid_not_found(payload: dict) -> bool:
    msg = (payload.get("ErrorMsg") or "").lower()
    return "submitid" in msg and "not found" in msg


def poll_until_finished_resilient(
    api_base: str,
    computation_id: str,
    submit_id: str,
    preferred_submit: str | None,
    poll_s: int,
    timeout_s: int,
) -> str:
    """
    Poll status for a submitId. If the API responds "SubmitId X not found",
    re-fetch CompInfo and switch to the newest available submitId, then continue.
    """
    t0 = time.time()
    current_sid = submit_id
    last_payload = None

    while True:
        payload = status(api_base, computation_id, current_sid)
        last_payload = payload

        st = payload.get("Status") or payload.get("status")
        msg = payload.get("ErrorMsg") or payload.get("Message") or ""
        print(f"[MOLE] {computation_id} submitId={current_sid} status={st} {msg}".strip(), flush=True)

        # Recover from transient "not found"
        if st == "Error" and is_submitid_not_found(payload):
            print("[MOLE] submitId not found -> refreshing CompInfo and retrying...", flush=True)
            compinfo = get_compinfo(api_base, computation_id)
            # try preferred first, then newest
            new_sid = pick_submit_id(compinfo, preferred=preferred_submit)
            if new_sid != current_sid:
                print(f"[MOLE] switching submitId {current_sid} -> {new_sid}", flush=True)
                current_sid = new_sid
            time.sleep(max(2, poll_s))
            continue

        if st in ("Finished", "Deleted", "Aborted"):
            if st != "Finished":
                raise RuntimeError(f"MOLE ended with status={st}. Payload: {payload}")
            return current_sid

        if st == "Error":
            raise RuntimeError(f"MOLE ended with status=Error. Payload: {payload}")

        if time.time() - t0 > timeout_s:
            raise TimeoutError(f"MOLE timed out after {timeout_s}s. Last payload: {last_payload}")

        time.sleep(poll_s)


def download(api_base: str, computation_id: str, submit_id: str, out_json: Path, out_report: Path) -> None:
    data_url = f"{api_base.rstrip('/')}/Data/{computation_id}"

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_report.parent.mkdir(parents=True, exist_ok=True)

    # JSON: prefer explicit submitId; fallback to "last computation"
    rj = requests.get(data_url, params={"submitId": submit_id}, timeout=120)
    if not rj.ok:
        rj = requests.get(data_url, timeout=120)
    rj.raise_for_status()
    out_json.write_text(rj.text, encoding="utf-8")

    # Report zip: explicit submitId (matches your working curl)
    rr = requests.get(data_url, params={"submitId": submit_id, "format": "report"}, timeout=300)
    rr.raise_for_status()
    out_report.write_bytes(rr.content)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-base", default="https://api.mole.upol.cz")
    ap.add_argument("--ids", required=True)
    ap.add_argument("--out-json", required=True)
    ap.add_argument("--out-report", required=True)
    ap.add_argument("--poll-seconds", type=int, default=15)
    ap.add_argument("--timeout-seconds", type=int, default=1800)
    args = ap.parse_args()

    ids_path = Path(args.ids)
    ids = json.loads(ids_path.read_text(encoding="utf-8"))

    comp_id = ids["computationId"]
    preferred_submit = str(ids.get("submitId", "")).strip() or None

    print(f"[MOLE] compinfo for computationId={comp_id}...", flush=True)
    compinfo = get_compinfo(args.api_base, comp_id)
    submit_id = pick_submit_id(compinfo, preferred=preferred_submit)
    print(f"[MOLE] using submitId={submit_id} (preferred was {preferred_submit})", flush=True)

    print("[MOLE] polling...", flush=True)
    resolved_sid = poll_until_finished_resilient(
        args.api_base, comp_id, submit_id, preferred_submit, args.poll_seconds, args.timeout_seconds
    )

    print("[MOLE] download...", flush=True)
    download(args.api_base, comp_id, resolved_sid, Path(args.out_json), Path(args.out_report))

    ids["resolvedSubmitId"] = resolved_sid
    ids_path.write_text(json.dumps(ids, indent=2), encoding="utf-8")
    print("[MOLE] done", flush=True)


if __name__ == "__main__":
    main()
