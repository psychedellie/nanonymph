consensus=$1
output=$2
db_res=$3

~/.local/bin/micromamba run -n gep-finders run_resfinder.py -ifa $consensus -db_res $db_res  --acquired --outputPath $output


