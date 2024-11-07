consensus=$1
output=$2
db_res=$3
db_point=$4
db_disinf=$5

~/.local/bin/micromamba run -n gep-finders run_resfinder.py -ifa $consensus -db_res $db_res -db_point $db_point -db_disinf $db_disinf --acquired --outputPath $output #--point


