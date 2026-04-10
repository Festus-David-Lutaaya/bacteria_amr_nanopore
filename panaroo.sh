#!/bin/bash

panaroo -i gffs/*.gff3 \
        -o panaroo_results \
        --clean-mode strict \
	    --remove-invalid-genes \
        -a core \
        --aligner mafft \
        --core_threshold 0.95

