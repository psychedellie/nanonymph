#!/bin/bash

np_raw_file=$1
unicycler_dir=$2
threads=$3
    
# Run Unicycler with long reads
~/.local/bin/micromamba run -n assembler unicycler --long $np_raw_file --out $unicycler_dir --threads $threads  # Specify output and threads.
