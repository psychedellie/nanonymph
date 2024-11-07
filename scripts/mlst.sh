consensus=$1
output_dir=$2
label=$3

~/.local/bin/micromamba run -n mlst mlst $consensus --label $label --quiet > $output_dir

