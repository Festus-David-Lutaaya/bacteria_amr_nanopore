#!/bin/bash
#SBATCH --job-name=iqtree_pipeline
#SBATCH --output=iqtree_%j.log
#SBATCH --error=iqtree_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --time=24:00:00
#SBATCH --mem=0

set -euo pipefail

iqtree3 -s panaroo_results/core_gene_alignment_filtered.aln -m MFP -bb 1000 -nt AUTO