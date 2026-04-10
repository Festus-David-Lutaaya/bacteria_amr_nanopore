#!/bin/bash
#SBATCH --job-name=panaroo_pipeline
#SBATCH --output=panaroo_%j.log
#SBATCH --error=panaroo_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --time=24:00:00
#SBATCH --mem=0

set -euo pipefail


panaroo -i gffs/*.gff3 \
        -o panaroo_results \
        --clean-mode strict \
	    --remove-invalid-genes \
        -a core \
        --aligner mafft \
        --core_threshold 0.95

