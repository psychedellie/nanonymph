#!/bin/bash

assembly=$1
output_dir=$2
np_raw_file=$3
threads=$4

# Run QUAST
micromamba run -n quast quast $assembly -o $output_dir --nanopore $np_raw_file  -t $threads
