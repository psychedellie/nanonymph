np_raw_file=$1
flye_dir=$2
threads=$3

# Run Flye assembler
micromamba run -n flye flye --nano-hq $np_raw_file --out-dir $flye_dir --deterministic --threads $threads # Specify output and threads
