np_raw_file=$1
flye_dir=$2
threads=$3

# Run Flye assembler
~/.local/bin/micromamba run -n flye flye --nano-raw $np_raw_file --out-dir $flye_dir --deterministic --threads $threads # Specify output and threads
