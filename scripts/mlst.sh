consensus=$1
output_dir=$2
label=$3

micromamba run -n mlst mlst $consensus --label $label --quiet > $output_dir

