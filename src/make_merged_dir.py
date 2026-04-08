#!/usr/bin/env python3
import sys
import re

try:
    import yaml
except ImportError as e:
    raise SystemExit("PyYAML is required (pip/conda install pyyaml).") from e


def slug(s: str) -> str:
    # keep only safe path chars
    return re.sub(r"[^A-Za-z0-9._-]+", "-", str(s))


def fmt_part(values, default: str) -> str:
    """Format list as: single -> 'X', multiple -> 'first-last', empty -> default."""
    if not values:
        return default
    vals = [slug(v) for v in values]
    if len(vals) == 1:
        return vals[0]
    return f"{vals[0]}-{vals[-1]}"


def fmt_models(models) -> str:
    """Format models as: single -> '00', multiple -> '00-01-02' (preserve given order)."""
    if not models:
        return "allmodels"
    vals = [slug(v) for v in models]
    return "-".join(vals)


def main(cfg_path: str) -> None:
    with open(cfg_path, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}

    pf = cfg.get("plot_filters") or {}

    run_part = fmt_part(pf.get("run_ids"), "allruns")

    seed_model = pf.get("seed_model")  # mapping: seed -> [models]
    if isinstance(seed_model, dict) and len(seed_model) > 0:
        # Paired format:
        # results/merged_<run>_<seed1>-<models>_<seed2>-<models>...
        parts = []
        for seed, models in seed_model.items():  # preserves YAML order (Python 3.7+)
            seed_s = slug(seed)
            # allow either a single string or a list
            if isinstance(models, (str, int)):
                models = [str(models)]
            elif models is None:
                models = []
            else:
                models = [str(m) for m in models]

            parts.append(f"{seed_s}-{fmt_models(models)}")

        out_dir = "results/merged_" + run_part + "_" + "_".join(parts)
        print(out_dir)
        return

    # Fallback (old behavior): independent lists (cartesian product semantics)
    seed_part  = fmt_part(pf.get("seed_ids"),  "allseeds")
    model_part = fmt_part(pf.get("model_ids"), "allmodels")

    out_dir = f"results/merged_{run_part}_{seed_part}_{model_part}"
    print(out_dir)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: make_merged_dir.py <config.yaml>")
    main(sys.argv[1])
