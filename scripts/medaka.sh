np_raw_file=$1
assembly=$3
output_dir=$2


if [ -d $output_dir ]; then
        echo "Deleting existing folder: $output_dir"
        rm -rf $output_dir
fi

~/.local/bin/micromamba run -n polisher medaka_consensus -i $np_raw_file -d $assembly -o $output_dir -m r1041_e82_400bps_sup_v4.3.0
