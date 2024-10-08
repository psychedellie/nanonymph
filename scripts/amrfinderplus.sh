consensus=$1
output=$2
db=$3
species_file=$4
threads=$5

if [ -f $species_file ]; then
  ~/.local/bin/micromamba run -n analysis amrfinder -n $consensus -o $output -d $db -O $(cat $species_file) --threads $5
else
  ~/.local/bin/micromamba run -n analysis amrfinder -n $consensus -o $output -d $db --threads $5
fi
