import os

def input_structure(wc):
    pdb = f"data/{wc.sample}.pdb"
    cif = f"data/{wc.sample}.cif"
    if os.path.exists(pdb):
        return pdb
    if os.path.exists(cif):
        return cif
    raise ValueError(
        f"No input structure found for sample {wc.sample} "
        f"(expected {pdb} or {cif})"
    )