consensus=$1
output=$2
db=$3

mkdir -p $output
~/.local/bin/micromamba run -n gep-finders plasmidfinder.py -i $consensus -p $db -x -o $output

