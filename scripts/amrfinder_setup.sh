db_root=$1
db_path=$db_root/amrfinder/

~/.local/bin/micromamba run -n analysis amrfinder_update -d $db_path
