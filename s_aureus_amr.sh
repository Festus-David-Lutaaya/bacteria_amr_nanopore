#!/bin/bash
#SBATCH --job-name=SAUREUS_PIPELINE
#SBATCH --output=saureus_%j.log
#SBATCH --error=saureus_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --time=72:00:00
#SBATCH --mem=0

set -euo pipefail

THREADS=${SLURM_CPUS_PER_TASK:-1}
INPUT_DIR="raw_data"

if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: raw_data folder not found!"
    exit 1
fi

for INPUT in "$INPUT_DIR"/*.fastq "$INPUT_DIR"/*.fastq.gz "$INPUT_DIR"/*.gz; do
    [ -e "$INPUT" ] || continue

    BASENAME=$(basename "$INPUT")
    SAMPLE=${BASENAME%%.*}

    SAMPLE_DIR="${SAMPLE}_Assembly_Results"
    BEFORE_DIR="$SAMPLE_DIR/before_trim"
    AFTER_DIR="$SAMPLE_DIR/after_trim"
    QC_DIR="$SAMPLE_DIR/qc"
    ASSEMBLY_DIR="$SAMPLE_DIR/assembly"
    ALIGN_DIR="$SAMPLE_DIR/alignment"
    POLISHED_DIR="$SAMPLE_DIR/polished"
    METRICS_DIR="$SAMPLE_DIR/metrics"
    PROKKA_DIR="$SAMPLE_DIR/prokka"
    AMR_DIR="$SAMPLE_DIR/amr"

    mkdir -p "$BEFORE_DIR" "$AFTER_DIR" "$QC_DIR" "$ASSEMBLY_DIR" "$ALIGN_DIR" "$POLISHED_DIR" "$METRICS_DIR" "$PROKKA_DIR" "$AMR_DIR"

    cp "$INPUT" "$BEFORE_DIR/"

    if [[ "$INPUT" == *.gz ]]; then
        cat_cmd="zcat"
    else
        cat_cmd="cat"
    fi

    echo "Processing $SAMPLE"

# ----------------------------
# QC BEFORE
# ----------------------------

    NanoPlot --fastq "$INPUT" --threads $THREADS \
    --plots hex dot kde --N50 --loglength \
    --outdir "$QC_DIR" --prefix "${SAMPLE}_pretrim"

# ----------------------------
# Filtering
# ----------------------------

    TRIMMED="$AFTER_DIR/${SAMPLE}_trimmed.fastq.gz"
    $cat_cmd "$INPUT" | NanoFilt -q 7 -l 500 | gzip > "$TRIMMED"

# ----------------------------
# QC AFTER
# ----------------------------

    NanoPlot --fastq "$TRIMMED" --threads $THREADS \
    --plots hex dot kde --N50 --loglength \
    --outdir "$QC_DIR" --prefix "${SAMPLE}_posttrim"

# ----------------------------
# Flye Assembly
# ----------------------------

    flye --nano-raw "$TRIMMED" \
         --genome-size 2.8m \
         --threads $THREADS \
         --out-dir "$ASSEMBLY_DIR"

    CONTIGS="$ASSEMBLY_DIR/assembly.fasta"

# ----------------------------
# Racon Round 1
# ----------------------------

    minimap2 -t $THREADS -x map-ont "$CONTIGS" "$TRIMMED" > "$ALIGN_DIR/round1.paf"

    racon -t $THREADS \
    "$TRIMMED" \
    "$ALIGN_DIR/round1.paf" \
    "$CONTIGS" \
    > "$POLISHED_DIR/racon_round1.fasta"

# ----------------------------
# Racon Round 2
# ----------------------------

    minimap2 -t $THREADS -x map-ont "$POLISHED_DIR/racon_round1.fasta" "$TRIMMED" > "$ALIGN_DIR/round2.paf"

    racon -t $THREADS \
    "$TRIMMED" \
    "$ALIGN_DIR/round2.paf" \
    "$POLISHED_DIR/racon_round1.fasta" \
    > "$POLISHED_DIR/racon_round2.fasta"

# ----------------------------
# Racon Round 3
# ----------------------------

    minimap2 -t $THREADS -x map-ont "$POLISHED_DIR/racon_round2.fasta" "$TRIMMED" > "$ALIGN_DIR/round3.paf"

    racon -t $THREADS \
    "$TRIMMED" \
    "$ALIGN_DIR/round3.paf" \
    "$POLISHED_DIR/racon_round2.fasta" \
    > "$POLISHED_DIR/consensus.fasta"

    POLISHED_CONTIGS="$POLISHED_DIR/consensus.fasta"

# ----------------------------
# Assembly metrics
# ----------------------------

    quast.py "$POLISHED_CONTIGS" --threads $THREADS -o "$METRICS_DIR"

# ----------------------------
# Annotation
# ----------------------------

    prokka \
    --outdir "$PROKKA_DIR" \
    --prefix "$SAMPLE" \
    --cpus $THREADS \
    --force \
    "$POLISHED_CONTIGS"

# ----------------------------
# AMR Detection
# ----------------------------

    for DB in card resfinder ncbi argannot; do
        abricate --threads $THREADS --db $DB "$POLISHED_CONTIGS" > "$AMR_DIR/${SAMPLE}_${DB}.txt"
    done

    abricate --summary "$AMR_DIR"/*.txt > "$AMR_DIR/${SAMPLE}_AMR_summary.txt"

    echo "Finished $SAMPLE"

done

echo "Assembly + AMR completed for all samples"
