np_raw_file=$1
assembly=$3
output_dir=$2

if [ -d $output_dir ]; then
        echo "Deleting existing folder: $output_dir"
        rm -rf $output_dir
fi

~/.local/bin/micromamba run -n medaka medaka_consensus -i $np_raw_file -d $assembly -o $output_dir 
