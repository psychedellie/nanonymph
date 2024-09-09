consensus=$1
output=$2
db=$3

mkdir -p $output
~/.local/bin/micromamba run -n analysis plasmidfinder.py -i $consensus -p $db -x -o $output

