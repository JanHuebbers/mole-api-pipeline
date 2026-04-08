#!/usr/bin/env python3
import argparse
import json
import time
from pathlib import Path

import requests


def _extract_id(payload, keys):
    if isinstance(payload, dict):
        for k in keys:
            if k in payload and payload[k] not in (None, ""):
                return payload[k]
        lower = {str(k).lower(): k for k in payload.keys()}
        for k in keys:
            if k.lower() in lower:
                return payload[lower[k.lower()]]
    if isinstance(payload, (str, int)):
        return payload
    return None


def init_computation(api_base: str, input_path: Path) -> str:
    # File upload endpoint
    url = f"{api_base.rstrip('/')}/Init"
    with input_path.open("rb") as f:
        r = requests.post(url, files={"file": (input_path.name, f)}, timeout=120)
    r.raise_for_status()
    payload = r.json()
    comp_id = _extract_id(payload, ["computationId", "ComputationId", "id", "Id"])
    if not comp_id:
        raise RuntimeError(f"Could not parse computationId from /Init response: {payload}")
    return str(comp_id)


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
        if sid is not None:
            out.append(str(sid))
    return out


def submit(api_base: str, mode: str, computation_id: str, params: dict, max_tries: int = 8) -> str:
    import time

    url = f"{api_base.rstrip('/')}/Submit/{mode}/{computation_id}"
    last_payload = None

    for attempt in range(1, max_tries + 1):
        r = requests.post(url, json=params, timeout=120)

        if r.status_code in (429, 502, 503, 504):
            wait_s = min(300, 10 * attempt)
            print(f"[MOLE] transient HTTP {r.status_code} on submit, retrying in {wait_s}s...", flush=True)
            time.sleep(wait_s)
            continue

        r.raise_for_status()
        payload = r.json()
        last_payload = payload
        print(f"[MOLE] raw /Submit payload: {payload}", flush=True)

        status = str(payload.get("Status", "")).strip()
        err = str(payload.get("ErrorMsg", "")).strip()
        submit_id = _extract_id(payload, ["submitId", "SubmitId", "id", "Id"])
        submit_id = None if submit_id is None else str(submit_id).strip()

        if status.lower() == "error":
            if "heavy load" in err.lower() or "try again later" in err.lower():
                wait_s = min(300, 15 * attempt)
                print(f"[MOLE] server under heavy load, retrying submit in {wait_s}s...", flush=True)
                time.sleep(wait_s)
                continue
            raise RuntimeError(f"/Submit returned error: {payload}")

        if submit_id in ("", "0", "None", "null"):
            wait_s = min(300, 15 * attempt)
            print(f"[MOLE] invalid submitId={submit_id}, retrying submit in {wait_s}s...", flush=True)
            time.sleep(wait_s)
            continue

        return submit_id

    raise RuntimeError(f"/Submit failed after {max_tries} attempts. Last payload: {last_payload}")


def resolve_submit_id(
    api_base: str,
    computation_id: str,
    initial_submit_id: str,
    timeout_s: int = 300,
    poll_s: int = 5,
) -> str:
    t0 = time.time()
    last_compinfo = None
    preferred = str(initial_submit_id).strip()

    while True:
        compinfo = get_compinfo(api_base, computation_id)
        last_compinfo = compinfo
        submit_ids = list_submit_ids(compinfo)

        if submit_ids:
            if preferred and preferred in submit_ids:
                return preferred

            def sid_key(x: str) -> int:
                try:
                    return int(x)
                except Exception:
                    return -1

            return sorted(submit_ids, key=sid_key)[-1]

        if time.time() - t0 > timeout_s:
            raise TimeoutError(
                f"No submissions appeared in CompInfo after {timeout_s}s. "
                f"initial_submit_id={initial_submit_id}; last CompInfo={last_compinfo}"
            )

        print(
            f"[MOLE] waiting for submission to appear in CompInfo for computationId={computation_id}...",
            flush=True,
        )
        time.sleep(poll_s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-base", default="https://api.mole.upol.cz")
    ap.add_argument("--mode", choices=["Pores", "Mole"], default="Pores")
    ap.add_argument("--input", required=True)
    ap.add_argument("--out-ids", required=True)
    ap.add_argument("--params-json", default="{}")
    args = ap.parse_args()

    inp = Path(args.input)
    out_ids = Path(args.out_ids)
    out_ids.parent.mkdir(parents=True, exist_ok=True)

    params = json.loads(args.params_json)

    print("[MOLE] init...", flush=True)
    comp_id = init_computation(args.api_base, inp)
    print(f"[MOLE] computationId={comp_id}", flush=True)

    print("[MOLE] submit...", flush=True)
    initial_submit_id = submit(args.api_base, args.mode, comp_id, params)
    print(f"[MOLE] initial submitId={initial_submit_id}", flush=True)

    submit_id = resolve_submit_id(args.api_base, comp_id, initial_submit_id)
    print(f"[MOLE] resolved submitId={submit_id}", flush=True)

    out_ids.write_text(
        json.dumps(
            {
                "computationId": comp_id,
                "submitId": submit_id,
                "mode": args.mode,
                "params": params,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"[MOLE] wrote IDs -> {out_ids}", flush=True)


if __name__ == "__main__":
    main()
