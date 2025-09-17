consensus=$1
output=$2
species_file=$3
threads=$4

if [ -f $species_file ]; then
  micromamba run -n amrfinderplus amrfinder -n $consensus -o $output -O $(cat $species_file) --threads $threads --plus
else
  micromamba run -n amrfinderplus amrfinder -n $consensus -o $output --threads $threads --plus
fi
