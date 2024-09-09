import yaml
import pandas as pd

organisms_yaml= "config/supported_organisms.yaml"
rmlst_file= "test/rmlst/687_rmlst.tsv"

with open(organisms_yaml, "r") as organism_file:
    supported_org= yaml.load(organism_file)

rmlst= pd.read_csv(rmlst_file, sep= "\t")

print(supported_org)
print(rmlst)
