
#!/usr/bin/env python3
# Upload contigs file to PubMLST rMLST species identifier via RESTful API
# Written by Keith Jolley
# Copyright (c) 2018, University of Oxford
# Licence: GPL3


import sys, requests, argparse, base64, os.path, yaml
import pandas as pd

parser = argparse.ArgumentParser()

parser.add_argument('--file', '-f', type=str, help='assembly contig filename (FASTA format)')

parser.add_argument(
        "--output",
        "-o",
        type=str,
        default = "rMLST.tsv",
        help = "File path to the output tsv file."
        )
        
parser.add_argument(
	"--organism_file",
	"-O",
	type=str,
	default=None,
	help = "YAML file containing supported organisms"
	)

parser.add_argument(
	"--species_file",
	"-s",
	type=str,
	help = "Write the species to a txt file if detected among the supported organisms."
	)
	
args = parser.parse_args()


def check_supported(supported_organisms, rmlst):
  Genus = rmlst['Genus'].iloc[0]
  Taxon = rmlst['Taxon'].iloc[0].replace(' ','_')
  
  if Genus in supported_organisms :
    return(Genus)
  elif Taxon in supported_organisms :
    return(Taxon)
  else:
    print("Organism not supported by AMRFinderPlus.")
    
  return(None)


def main(assembly_file):
    uri = 'http://rest.pubmlst.org/db/pubmlst_rmlst_seqdef_kiosk/schemes/1/sequence'
    with open(args.file, 'r') as x: 
        fasta = x.read()
        
    print("Encoding fasta", flush = True)
    payload = '{"base64":true,"details":true,"sequence":"' + base64.b64encode(fasta.encode()).decode() + '"}'
    response = requests.post(uri, data=payload)
    if response.status_code == requests.codes.ok:
        data = response.json()
        try: 
            data['taxon_prediction']
        except KeyError:
            print("No match")
            sys.exit(0)

        print("Collecting results", flush = True)
        # Corrected way to extract the sample name

        match = pd.DataFrame(columns=["Genus", "Species", "Taxon", "Abbreviated", "Rank", "Percentage"])

        for result in data['taxon_prediction']:
                Rank = result['rank']
                Taxon = result['taxon']
                Genus = Taxon.split()[0]
                Species = Taxon.split()[1]
                Support = result['support']
                Taxonomy = result['taxonomy']
                Abbreviated = f"{Genus[0]}. {Species}"

                match.loc[len(match.index)] = [Genus, Species, Taxon, Abbreviated, Rank, Support]  
            
    else:
        print(response.text)

    return match

if __name__ == "__main__":
    rmlst = main(args.file)
    
    if args.organism_file is not None :
      with open(args.organism_file, "r") as organism_read:
        supported_organisms = yaml.safe_load(organism_read)
      
      amfinder_organisms = supported_organisms.get("amrfinder")
      species = check_supported(supported_organisms=amfinder_organisms, rmlst=rmlst)
      
      if species is not None:
        with open(args.species_file, "w") as species_write:
          species_write.write(species)
    
    output = args.output
    
    output_dir = os.path.dirname(output)
    if not os.path.isdir(output_dir) :
      print(f"Creating directory: {output_dir}")
      os.makedirs(output_dir, exist_ok=True)

    rmlst.to_csv(output, sep = "\t", index = False)
