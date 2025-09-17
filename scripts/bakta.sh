consensus=$1
output=$2
sample_name=$3
threads=$4
database=$5

micromamba run -n bakta bakta $consensus --output $output --prefix $sample_name --threads $threads --db $database
  
