# mole-api-pipeline
A Snakemake-based workflow for preparing .pdb input structures, submitting remote MOLE API jobs, collecting pore/channel analysis results, and generating downstream plots from MD-derived protein structures.
# Table of contents
- Overview
- Features
- Notes
- Repository layout
- Requirements
- Installation
- Quick start
- Workflow
  1. Create input
  2. Ensure that PDB filenames follow the required naming scheme
  3. Run the full pipeline
  4. Re-run only a specific part by targeting an output
  5. Limit concurrent MOLE API usage
  6. Result collection and aggregation
  7. Plotting and merged plots
- Typical workflow
- Status
# Overview
`mole-api-pipeline` is a modular Snakemake workflow for preparing .pdb protein structure inputs from .cxs files, renaming MD-derived PDB files into MOLE-compatible identifiers, submitting remote MOLE API jobs, polling and collecting finished runs, and generating pore-analysis plots. It is designed for Ubuntu _via_ WSL on Windows, but can also be adapted to other Linux environments.
# Features
- Remote execution of MOLE API jobs from local structure files
- Snakemake-based orchestration of submission, polling, collection, and plotting
- ChimeraX `.cxs` to `.pdb` export helper script
- File-name translation from MD naming schemes to MOLE-accessible IDs
- Configurable concurrency control for remote MOLE API usage
- Sample-level pore outline plots
- Merged pore plots across selected result sets
- Recovery-friendly reruns by targeting downstream outputs
- Designed for Linux and WSL-based workflows
# Notes
- This workflow currently assumes a Linux-style environment.
- The pipeline was written for Ubuntu on WSL.
- ChimeraX paths may need manual adjustment in `./cxs/chimeraX_path.yml`.
- MOLE API jobs are remote and may queue depending on server load.
- If you manually copy files from Windows into WSL, you may need ownership and permission fixes.
- This workflow integrates well with structures derived from AlphaFold 3 predictions _via_ [af3-server-workflow](https://github.com/JanHuebbers/af3-server-workflow).
# Repository layout
```text
mole-api-pipeline/
├── README.md
├── Snakefile
├── config.yaml
├── cxs
├── data
├── envs
├── logs
├── results
├── rules
└── src
```
# Requirements
## System
- Linux environment
- Conda, Miniconda, or Mamba
- Python
- Snakemake
- ChimeraX (for `.cxs` export)
- Internet access for remote MOLE API submission

**Recommended environment: Ubuntu or Ubuntu via WSL on Windows.**
# Installation
## 1. Install Snakemake
Follow the official [Snakemake documentation](https://snakemake.readthedocs.io/en/stable/index.html) to install Snakemake. The setup described in this repository uses [Miniforge](https://github.com/conda-forge/miniforge).
## 2. Clone the repository
```bash
git clone <your-repository-url>
cd mole-api-pipeline
```
## 3. Configure Conda channels and environments
**Load Miniforge:**
```bash
source ~/miniforge3/etc/profile.d/conda.sh
which conda
```
**To avoid version conflicts when installing packages:**
```bash
conda config --add channels conda-forge
conda config --set channel_priority strict
```
This configures Conda to install packages from conda-forge with strict channel priority, which helps avoid version conflicts and improves environment consistency. If users already have several channels configured, `--add channels conda-forge` appends it to the list, so priority depends on the existing order.

**Create the environments:**
```bash
conda env create -f envs/snakemake_env.yml
conda env create -f envs/mole_env.yml
```
**Or update if these environments already exist:**
```bash
conda env update -f envs/snakemake_env.yml --prune
conda env update -f envs/mole_env.yml --prune
```
## 4. Configure ChimeraX path  
Edit `./cxs/chimeraX_path.yml` to point to your ChimeraX executable. **For WSL, the path may look like this:**
```yaml
chimerax_path: "/mnt/c/Program Files/ChimeraX 1.10.1/bin/ChimeraX-console.exe"
```
**Verify ChimeraX accessibility on WSL:**
```bash
"/mnt/c/Program Files/ChimeraX 1.10.1/bin/ChimeraX-console.exe" --version
```

## 5. Prepare input folders  
**Create or populate the folders used by the workflow, especially:**
- `cxs/` for ChimeraX session files
- `data/` for exported or renamed PDBs
- `logs/` for logs
- `results/` for MOLE outputs and plots
```bash
mkdir -p cxs data logs results
```
# Quick start
## 1. Activate the Conda environment
```bash
source ~/miniforge3/etc/profile.d/conda.sh
conda activate snakemake_env
```
## 2. (Optional) Export `.pdb` files from ChimeraX `.cxs` files
Use this step for `.cxs` files that contain multiple structures retrieved from AF3 predictions with [af3-server-workflow](https://github.com/JanHuebbers/af3-server-workflow):
```bash
python src/run_cxs_to_pdb.py ./cxs/0001_01_1710.cxs data
```
## 4. Run the full Snakemake pipeline
```bash
snakemake -j 1 --use-conda
```
To test the pipeline without executing any rules, run a **dry run**:
```bash
snakemake -n -p
```
# Workflow
The Snakemake workflow handles the main remote MOLE execution sequence:
- initialize a computation
- submit a MOLE or Pores run
- poll status until completion
- collect final outputs
- write sample-level result files
- merge selected outputs into long-format tables
- plot pore profiles

**Activate the environment:**
```bash
source ~/miniforge3/etc/profile.d/conda.sh
conda activate snakemake_env
```
## 1. Create input
Create `.pdb` files from ChimeraX `.cxs` files.
**Default:**
```bash
python src/run_cxs_to_pdb.py ./cxs/0001_01_1710.cxs data
```
**Override prefix and model count:**
```bash
python src/run_cxs_to_pdb.py ./cxs/0001_01_1710_AtMLO1_AtCAM2.cxs data 0001_01_1710 5
```
**Important**  
If you manually copy and rename `.cxs` or `.pdb` files from Windows to WSL, update the ownership and permissions:
```bash
sudo chown -R "$USER":"$USER" ./data
chmod -R u+rwX ./data
```
## 2. Ensure that PDB filenames follow the required naming scheme
Each `.pdb` file must use a prefix that can be parsed by the pipeline. This naming convention is historically based on the [af3-server-workflow](https://github.com/JanHuebbers/af3-server-workflow) and is built from the AF3 RunID, JobID, Seed, and ModelID:
`<AAAA(RunID)>_<BB(JobID)>_<CCCC(Seed)>_<DD(ModelID)>`
**Alternatively, copy `.pdb` files with the desired prefix into `./data`.**
This prefix identifies a single structure and is used for filtering and plotting pore profiles. In the current version, gradient colors and point shapes are mapped according to seed values.

### Color definitions in `P1_poreprofile_perPDB.R` and `P2_poreprofile_merged.R`
The plotting scripts in `./src/R/` use fixed seed-level color definitions to ensure reproducible and comparable plot aesthetics across all outputs.

A selected group of AF3 seeds is assigned colors from a predefined gradient, while other seeds are mapped to manually specified fixed colors. Both mappings are merged into a single color table and applied consistently during plotting.

This approach ensures that the same seed is always represented by the same color across sample-level and merged pore profile plots. In the current version, color is mapped to seed values extracted from the filename prefix.

## 3. Run the full pipeline
Adjust the desired MOLE parameters, such as `poremode` and `probe radius`, in `config.yaml`.
**Default:**
```bash
snakemake -j 1 --use-conda
```
**Verbose:**
```bash
snakemake -j 1 --use-conda -p
```
**Dry run:**
```bash
snakemake -npr --use-conda
```
## 4. Re-run only a specific part by targeting an output
**Retry collection without resubmitting:**
```bash
snakemake -j 1 --use-conda results/0001_01_1710_00/results.json
```
**Run downstream steps for merged tables:**
```bash
snakemake -j 1 --use-conda results/pore_data_long.csv results/physchem_long.csv
```
## 5. Limit concurrent MOLE API usage
You can allow high overall pipeline parallelism while restricting how many remote MOLE jobs run simultaneously.
**One MOLE job at a time:**
```bash
snakemake -j 100 --use-conda --resources mole_api=1 -p
```
**Two concurrent MOLE jobs:**
```bash
snakemake -j 20 --use-conda --resources mole_api=2 -p
```
This is useful because:
- `-j` controls total pipeline parallelism
- `--resources mole_api=N` limits rules that consume `mole_api=1`
- this is ideal for remote APIs with queue or rate limitations
## 6. Result collection and aggregation
Typical collected outputs include:
- `results.json`
- pore-related `.csv` tables
- merged result tables such as:
  - `results/pore_data_long.csv`
  - `results/physchem_long.csv`
Because collection is separated from submission in the dependency graph, it is often possible to rerun downstream collection or aggregation without resubmitting finished jobs.
## 7. Plotting and merged plots
### Plot one sample
Force regeneration of one pore outline plot:
```bash
snakemake --use-conda -j 1 \
  --allowed-rules plot_sample_pore \
  --forcerun plot_sample_pore -- \
  results/0001_01_1710_00/pore_outline_rel.svg
```
### Plot all existing sample pore outlines
This finds all `results/*/pore_data.csv` files and maps them to their corresponding SVG targets:
```bash
snakemake --use-conda -j 1 \
  --allowed-rules plot_sample_pore \
  --forcerun plot_sample_pore -- \
  $(find results -maxdepth 2 -name pore_data.csv -print \
    | sed 's#/pore_data\.csv$#/pore_outline_rel.svg#')
```
### Merged plots
The merged output folder is computed from the active config:
```bash
python src/make_merged_dir.py config.yaml
```
**Example folder format:**
```bash
results/merged_0001_1710-1705_00-01/
```
**Run merged pore plotting:**
```bash
MERGED_DIR=$(python src/make_merged_dir.py config.yaml)
snakemake --use-conda -j 1 \
  --allowed-rules plot_merged_pores \
  --forcerun plot_merged_pores -- \
  "$MERGED_DIR/pore_outlines_merged_D.svg"
```
# Troubleshooting
## The run looks “stuck” after activation
MOLE API execution is remote and may queue. With progress prints enabled, you should typically see:
- `status=Initializing`
- `status=Initialized`
- `status=Running`
- `status=Finished`
If a run remains in `Initialized` for a long time, this is usually due to remote server load or queueing.
## Inspect a running computation manually
**Example IDs:**
```bash
COMP=ZuNpSdHKgkqnGx29W8GQ
SUB=1
```
**Check status:**
```bash
curl "https://api.mole.upol.cz/Status/$COMP?submitId=$SUB"
```
**Inspect what the server has registered for the computation:**
```bash
curl "https://api.mole.upol.cz/CompInfo/$COMP"
```
**Optional version check:**
```bash
curl "https://api.mole.upol.cz/Version"
```
## JSON decode errors for parameters
Ensure parameters are passed as valid JSON:
- use double quotes
- use `true` and `false`
- avoid Python-style single-quoted dictionaries

The Snakemake workflow should typically generate parameter JSON through `json.dumps()` to avoid malformed requests.

# Typical workflow
- set up the environment
- configure ChimeraX access
- export `.pdb` files from `.cxs` sessions if needed, or submit `.pdb` files directly to `data/` following the naming convention
- rename or translate structure file names into MOLE-accessible IDs
- populate `data/` with input PDB files
- run the Snakemake pipeline
- monitor remote MOLE API progress
- collect result files under `results/`
- generate sample-level pore plots
- generate merged plots for selected configurations
# Status
- PDB export: active
- name translation workflow: active
- remote MOLE API execution: active
- result collection: active
- plotting: active
- merged plotting: active
