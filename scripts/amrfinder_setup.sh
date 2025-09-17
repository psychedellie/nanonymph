db_root=$1
db_path=$db_root/amrfinder/

micromamba run -n amrfinderplus amrfinder_update -d $db_path
