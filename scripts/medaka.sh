np_raw_file=$1
output_dir=$2
assembly=$3
threads=$4
model=$5

if [ -d $output_dir ]; then
        echo "Deleting existing folder: $output_dir"
        rm -rf $output_dir
fi

micromamba run -n medaka medaka_consensus -i $np_raw_file -d $assembly -o $output_dir -t $threads --bacteria -m $model
