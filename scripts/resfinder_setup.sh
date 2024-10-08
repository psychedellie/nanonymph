db_root=$1
rf_db_path=$db_root/resfinder_db/
pf_db_path=$db_root/pointfinder_db/
df_db_path=$db_root/disinfinder_db/

git clone https://bitbucket.org/genomicepidemiology/resfinder_db/ $rf_db_path
git clone https://bitbucket.org/genomicepidemiology/pointfinder_db/ $pf_db_path
git clone https://bitbucket.org/genomicepidemiology/disinfinder_db/ $df_db_path
