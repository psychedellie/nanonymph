#!/bin/bash

export PATH="/home/psychedellie/.local/bin:$PATH"

# Set default values for optional arguments
threads=3  # Default number of threads if not provided
db_root=databases # Default database directory

# Initialize variables for required arguments (these must be passed by the user)
input_dir=""
output_dir=""
basecaller=""

# Parse arguments passed to the script
# -d: Path to the database root (optional)
# -i: Path to the input directory (required)
# -o: Path to the output directory (required)
# -t: Number of threads to use (optional)
# -b: Basecaller model (optional)

while getopts ":d:i:o:t:m:" option; do
    case $option in
        d) db_root=$OPTARG;;  	 # Set database directory
        i) input_dir=$OPTARG;;   # Set input directory
        o) output_dir=$OPTARG;;  # Set output directory
        t) threads=$OPTARG;;  	 # Override default threads if provided
		m) model=$OPTARG;; 		 # Set basecaller model
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1;;  # Handle invalid options
    esac
done

# Ensure all arguments are provided
if [ -z "$db_root" ] || [ -z "$input_dir" ] || [ -z "$output_dir" ] || [ -z "$threads" ]; then
    echo "Usage: $0 -d <db_root> -i <input_dir> -o <output_dir> -t <threads>"
    echo "  -d: Path to the database root (required)"
    echo "  -i: Path to the input directory (required)"
    echo "  -o: Path to the output directory (required)"
    echo "  -t: Number of threads to use (optional, default: 3)"
	echo "  -b: Basecaller model"
    exit 1
fi

# Print the configuration to verify the arguments being used
echo "=============================="
echo "Configuration:"
echo "Database Root:      $db_root"  	# Path to the database root directory
echo "Input Directory:    $input_dir"   # Path where input FASTQ files are located
echo "Output Directory:   $output_dir"  # Path where output results will be saved
echo "Threads:            $threads"  	# Number of threads for processing
echo "Basecaller Model:	  $basecaller"  # Basecaller model
echo "=============================="

# Define paths for the databases, assuming they are subdirectories within $db_root
db_plasm=$db_root/plasmidfinder/  # Path to the PlasmidFinder database
db_bakta=$db_root/db-light

# Path to the file that contains supported organism information
organism_file=scripts/config/supported_organisms.yaml

# Define result directories where output data will be stored
results_dir=$output_dir/Results/  			  # Main results directory
consensus_dir=$results_dir/Fasta	  		  # Directory for consensus sequences
mlst_dir=$results_dir/MLST  				  # Directory for MLST results
plasmidfinder_dir=$results_dir/PlasmidFinder  # Directory for PlasmidFinder results
amrfinder_dir=$results_dir/AMRFinderPlus  	  # Directory for AMRFinderPlus results
filtered_outdir=$output_dir/filtered_reads


# Create result directories if they do not already exist
mkdir -p $consensus_dir $mlst_dir $plasmidfinder_dir $amrfinder_dir $resfinder_dir $filtered_outdir

# ADDED: Skip fastplong if filtered reads already exist
if find "$filtered_outdir" -maxdepth 1 -iname "*.fastq.gz" | read -r _; then
  echo "Filtered reads detected in $filtered_outdir — skipping fastplong."
else
  # Run fastplong
  bash scripts/fastplong.sh $input_dir $filtered_outdir $threads > "$filtered_outdir/fastplong.log" 2>&1
fi

# Loop through all .fastq.gz files in raw reads directory
for np_raw_file in $(find $filtered_outdir -maxdepth 1 -iname "*.fastq.gz") ; do
   	# Extract the sample name without the .fastq.gz extension
	sample=$(basename "$np_raw_file" .fastq.gz)

	echo $sample

	# Create log directory for each sample
	log_dir=$output_dir/logs/$sample
	mkdir -p "$log_dir"
	
	# Assemblying with Flye
	echo "Assemblying with Flye..."
	flye_dir=$output_dir/flye/$sample
	flye_assembly=$flye_dir/assembly.fasta
	if [ ! -f $flye_assembly ];then
	  mkdir -p "$flye_dir"  # Ensure the directory exists
	  sh scripts/flye.sh $np_raw_file $flye_dir $threads > "$log_dir/flye.log" 2>&1
	else
	  echo "Assembly file detected, skipping assembly: $flye_assembly"
	fi

	# Polishing assemblies
	echo "Polishing assemblies..."
	flye_medaka=$flye_dir/medaka
	flye_consensus=$flye_medaka/consensus.fasta
	if [ ! -f $flye_consensus ]; then
	  mkdir -p "$flye_medaka"  # Ensure the directory exists
	  sh scripts/medaka.sh $np_raw_file $flye_medaka $flye_assembly $threads > "$log_dir/medaka_flye.log" 2>&1
	else
	  echo "Consensus file detected, skipping polishing: $flye_consensus"
	fi

    	# Annotation with Bakta on consensus
    	echo "Annotating consensus with Bakta..."
    	flye_bakta_dir=$flye_dir/bakta
    	# ADDED: Skip Bakta if output directory already has files
    	if [ -d "$flye_bakta_dir" ] && [ -n "$(ls -A "$flye_bakta_dir" 2>/dev/null)" ]; then
    	  echo "Bakta output detected, skipping: $flye_bakta_dir"
    	else
    	  sh scripts/bakta.sh $flye_consensus $flye_bakta_dir $sample $threads $db_bakta > "$log_dir/bakta_flye.log" 2>&1
    	fi
    
	# rMLST on consensus
	echo "Performing rMLST on consensus..."
	species_flye_file=$flye_dir/$sample.species
	flye_rmlst=$flye_dir/"${sample}"_flye_rmlst.tsv
	# ADDED: Skip rMLST if outputs already exist
	if [ -s "$flye_rmlst" ] && [ -s "$species_flye_file" ]; then
	  echo "rMLST outputs detected, skipping: $flye_rmlst and $species_flye_file"
	else
	  sh scripts/run_rmlst.sh $flye_consensus $flye_rmlst $organism_file $species_flye_file scripts > "$log_dir/rmlst_flye.log" 2>&1
	fi

	# MLST on consensus
	echo "Performing MLST on consensus..."
	flye_mlst=$flye_dir/mlst.tsv 
	# ADDED: Skip MLST if output already exists
	if [ -s "$flye_mlst" ]; then
	  echo "MLST output detected, skipping: $flye_mlst"
	else
	  sh scripts/mlst.sh $flye_consensus $flye_mlst $sample > "$log_dir/mlst_flye.log" 2>&1
	fi

	# PlasmidFinder on consensus
	echo "PlasmidFinder on consensus..."
	flye_plasfinder=$flye_dir/plasmidfinder 
	# ADDED: Skip PlasmidFinder if output directory already has files
	if [ -d "$flye_plasfinder" ] && [ -n "$(ls -A "$flye_plasfinder" 2>/dev/null)" ]; then
	  echo "PlasmidFinder output detected, skipping: $flye_plasfinder"
	else
	  sh scripts/plasmidfinder.sh $flye_consensus $flye_plasfinder $db_plasm > "$log_dir/plasmidfinder_flye.log" 2>&1
	fi

	# AMRFinderPlus on consensus
	echo "AMRFinderPlus on consensus..."
	flye_amrfinder=$flye_dir/"${sample}"_flye_amrf.txt
	# ADDED: Skip AMRFinderPlus if output already exists
	if [ -s "$flye_amrfinder" ]; then
	  echo "AMRFinderPlus output detected, skipping: $flye_amrfinder"
	else
	  sh scripts/amrfinderplus.sh $flye_consensus $flye_amrfinder $species_flye_file $threads > "$log_dir/amrfinder_flye.log" 2>&1
	fi
	
	# Collecting results
	cp $flye_consensus $results_dir/Fasta/"$sample"_flye.fasta
	cp $flye_mlst $results_dir/MLST/"$sample"_flye.tsv
	cp -r $flye_plasfinder $results_dir/PlasmidFinder/"$sample"_flye
	cp $flye_amrfinder $results_dir/AMRFinderPlus/"$sample"_flye.txt	

done

# ADDED: Skip report generation if an HTML report already exists in AMRFinderPlus dir
if ls "$results_dir/AMRFinderPlus/"*.html >/dev/null 2>&1; then
  echo "AMRFinderPlus HTML report already present — skipping report generation."
else
  bash scripts/generate_html.sh $results_dir/AMRFinderPlus/
fi
