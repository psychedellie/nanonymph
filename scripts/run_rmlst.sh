consensus=$1
rmlst=$2
organism_file=$3
species_file=$4
scripts_dir=$5
    
~/.local/bin/micromamba run -n analysis python "$scripts_dir"/rmlst.py --file $consensus --output $rmlst --organism_file $organism_file --species_file $species_file
