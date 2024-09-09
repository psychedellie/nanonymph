consensus=$1
output=$2
sample_name=$3

~/.local/bin/micromamba run -n assembler prokka --outdir $output --prefix $sample_name $consensus #--quiet
