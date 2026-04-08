configfile: "config.yaml"

import os, glob, json, subprocess
from os.path import basename, splitext

include: "rules/common.smk"

# --------------------------------------------------------------------
# Configured merged output directory
# --------------------------------------------------------------------
MERGED_DIR = subprocess.check_output(
    ["python", "src/make_merged_dir.py", "config.yaml"],
    text=True
).strip()

# --------------------------------------------------------------------
# Sample discovery: any data/<sample>.pdb or data/<sample>.cif
# --------------------------------------------------------------------
SAMPLES = sorted(
    set([splitext(basename(p))[0] for p in glob.glob("data/*.pdb")] +
        [splitext(basename(p))[0] for p in glob.glob("data/*.cif")])
)

# --------------------------------------------------------------------
# Final targets
# --------------------------------------------------------------------
rule all:
    input:
        expand("results/{sample}/results.json", sample=SAMPLES),
        expand("results/{sample}/report.zip", sample=SAMPLES),
        expand("results/{sample}/pore_data.csv", sample=SAMPLES),
        expand("results/{sample}/physchem.csv", sample=SAMPLES),
        "results/pore_data_long.csv",
        "results/physchem_long.csv",
        expand("results/{sample}/pore_outline_rel.svg", sample=SAMPLES),
        expand("results/{sample}/pore_outline.rds", sample=SAMPLES),
        expand("results/{sample}/pore_data_R.csv", sample=SAMPLES),
        f"{MERGED_DIR}/pore_outlines_merged_T.svg",
        f"{MERGED_DIR}/pore_outlines_merged_T.rds",
        f"{MERGED_DIR}/pore_outlines_merged_D.svg",
        f"{MERGED_DIR}/pore_outlines_merged_D.rds"

rule mole_submit:
    input:
        structure=input_structure
    output:
        ids="results/{sample}/mole_ids.json"
    log:
        "logs/mole_submit/{sample}.log"
    conda:
        "envs/mole_env.yml"
    resources:
        mole_api=1
    params:
        api_base=lambda wc: config["api_base"],
        mode=lambda wc: config.get("mode", "Pores"),
        params_json=lambda wc: json.dumps(config.get("pores", {}))
    shell:
        r"""
        python src/mole_submit.py \
          --api-base "{params.api_base}" \
          --mode "{params.mode}" \
          --input "{input.structure}" \
          --out-ids "{output.ids}" \
          --params-json '{params.params_json}' \
          > "{log}" 2>&1
        """

rule mole_collect:
    input:
        ids="results/{sample}/mole_ids.json"
    output:
        json="results/{sample}/results.json",
        report="results/{sample}/report.zip"
    log:
        "logs/mole_collect/{sample}.log"
    conda:
        "envs/mole_env.yml"
    resources:
        mole_api=1
    params:
        api_base=lambda wc: config["api_base"],
        poll=lambda wc: int(config.get("poll_seconds", 15)),
        timeout=lambda wc: int(config.get("timeout_seconds", 1800))
    shell:
        r"""
        python src/mole_collect.py \
          --api-base "{params.api_base}" \
          --ids "{input.ids}" \
          --out-json "{output.json}" \
          --out-report "{output.report}" \
          --poll-seconds {params.poll} \
          --timeout-seconds {params.timeout} \
          > "{log}" 2>&1
        """

rule extract_tables:
    input:
        report="results/{sample}/report.zip",
        ids="results/{sample}/mole_ids.json"
    output:
        pore="results/{sample}/pore_data.csv",
        phys="results/{sample}/physchem.csv"
    log:
        "logs/extract_tables/{sample}.log"
    conda:
        "envs/mole_env.yml"
    shell:
        r"""
        python src/pores_extract.py \
          --sample "{wildcards.sample}" \
          --report-zip "{input.report}" \
          --mole-ids "{input.ids}" \
          --out-pore "{output.pore}" \
          --out-physchem "{output.phys}" \
          > "{log}" 2>&1
        """

rule merge_pore_tables:
    input:
        expand("results/{sample}/pore_data.csv", sample=SAMPLES)
    output:
        "results/pore_data_long.csv"
    log:
        "logs/merge_pore_tables.log"
    conda:
        "envs/mole_env.yml"
    shell:
        r"""
        python src/pores_merge.py \
          --inputs {input} \
          --out "{output}" \
          > "{log}" 2>&1
        """

rule merge_physchem_tables:
    input:
        expand("results/{sample}/physchem.csv", sample=SAMPLES)
    output:
        "results/physchem_long.csv"
    log:
        "logs/merge_physchem_tables.log"
    conda:
        "envs/mole_env.yml"
    shell:
        r"""
        python src/pores_merge.py \
          --inputs {input} \
          --out "{output}" \
          > "{log}" 2>&1
        """

rule plot_sample_pore:
    input:
        csv="results/{sample}/pore_data.csv",
        cfg="config.yaml"
    output:
        svg_rel="results/{sample}/pore_outline_rel.svg",
        rds="results/{sample}/pore_outline.rds",
        csv="results/{sample}/pore_data_R.csv"
    log:
        "logs/plot_sample_pore/{sample}.log"
    conda:
        "envs/mole_env.yml"
    shell:
        r"""
        python src/run_r_plot.py \
          --script src/R/P1_poreprofile_perPDB.R \
          --args "{input.cfg}" "{input.csv}" "{output.svg_rel}" "{output.rds}" "{output.csv}" "{wildcards.sample}" \
          > "{log}" 2>&1
        """

rule plot_merged_pores:
    input:
        csv="results/pore_data_long.csv",
        cfg="config.yaml"
    output:
        svg_T=f"{MERGED_DIR}/pore_outlines_merged_T.svg",
        rds_T=f"{MERGED_DIR}/pore_outlines_merged_T.rds",
        svg_D=f"{MERGED_DIR}/pore_outlines_merged_D.svg",
        rds_D=f"{MERGED_DIR}/pore_outlines_merged_D.rds"
    log:
        "logs/plot_merged_pores.log"
    conda:
        "envs/mole_env.yml"
    shell:
        r"""
        python src/run_r_plot.py \
          --script src/R/P2_poreprofile_merged.R \
          --args "{input.cfg}" "{input.csv}" "{output.svg_T}" "{output.rds_T}" "{output.svg_D}" "{output.rds_D}" \
          > "{log}" 2>&1
        """