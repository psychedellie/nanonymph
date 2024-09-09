db_root=db
rf_db_path=$db_root/resfinder_db/blast
pf_db_path=$db_root/pointfinder_db/blast
df_db_path=$db_root/disinfinder_db/blast

git clone https://bitbucket.org/genomicepidemiology/resfinder_db/ $rf_db_path
git clone https://bitbucket.org/genomicepidemiology/pointfinder_db/ $pf_db_path
git clone https://bitbucket.org/genomicepidemiology/disinfinder_db/ $df_db_path
