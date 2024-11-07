#!/bin/bash

# Set default values for optional arguments
threads=3  # Default number of threads if not provided

# Initialize variables for required arguments (these must be passed by the user)
input_dir=""
output_dir=""

# Parse arguments passed to the script
# -d: Path to the database root (optional)
# -i: Path to the input directory (required)
# -o: Path to the output directory (required)
# -t: Number of threads to use (optional)
while getopts ":d:i:o:t:" option; do
    case $option in
        d) db_root=$OPTARG;;  # Set database directory
        i) input_dir=$OPTARG;;  # Set input directory
        o) output_dir=$OPTARG;;  # Set output directory
        t) threads=$OPTARG;;  # Override default threads if provided
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
    exit 1
fi

# Print the configuration to verify the arguments being used
echo "=============================="
echo "Configuration:"
echo "Database Root:      $db_root"  # Path to the database root directory
echo "Input Directory:    $input_dir"  # Path where input FASTQ files are located
echo "Output Directory:   $output_dir"  # Path where output results will be saved
echo "Threads:            $threads"  # Number of threads for processing
echo "=============================="

# Define paths for the databases, assuming they are subdirectories within $db_root
db_plasm=$db_root/plasmidfinder/  # Path to the PlasmidFinder database
db_res=$db_root/resfinder/  # Path to the ResFinder database
db_amrf=$db_root/amrfinder/latest  # Path to the latest AMRFinder database

# Path to the file that contains supported organism information
organism_file=scripts/config/supported_organisms.yaml

# Define result directories where output data will be stored
results_dir=$output_dir/Results/  # Main results directory
consensus_dir=$results_dir/Consensus  # Directory for consensus sequences
mlst_dir=$results_dir/MLST  # Directory for MLST results
plasmidfinder_dir=$results_dir/PlasmidFinder  # Directory for PlasmidFinder results
amrfinder_dir=$results_dir/AMRFinderPlus  # Directory for AMRFinderPlus results
resfinder_dir=$results_dir/ResFinder  # Directory for ResFinder results

# Create result directories if they do not already exist
mkdir -p $consensus_dir $mlst_dir $plasmidfinder_dir $amrfinder_dir $resfinder_dir

# Loop through all .fastq.gz files in raw reads directory
for np_raw_file in $(find $input_dir -maxdepth 1 -iname "*.fastq.gz") ; do
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
	  sh scripts/medaka.sh $np_raw_file $flye_medaka $flye_assembly > "$log_dir/medaka_flye.log" 2>&1
	else
	  echo "Consensus file detected, skipping polishing: $flye_consensus"
	fi

    	# Annotation with Prokka on consensus
    	echo "Annotating consensus with Prokka..."
    	flye_prokka_dir=$flye_dir/prokka
    	sh scripts/prokka.sh $flye_consensus $flye_prokka_dir $sample > "$log_dir/prokka_flye.log" 2>&1
    
	# rMLST on consensus
	echo "Performing rMLST on consensus..."
	species_flye_file=$flye_dir/$sample.species
	flye_rmlst=$flye_dir/"${sample}"_flye_rmlst.tsv
	sh scripts/run_rmlst.sh $flye_consensus $flye_rmlst $organism_file $species_flye_file scripts > "$log_dir/rmlst_flye.log" 2>&1

	# MLST on consensus
	echo "Performing MLST on consensus..."
	flye_mlst=$flye_dir/mlst.tsv 
	sh scripts/mlst.sh $flye_consensus $flye_mlst $sample > "$log_dir/mlst_flye.log" 2>&1

	# PlasmidFinder on consensus
	echo "PlasmidFinder on consensus..."
	flye_plasfinder=$flye_dir/plasmidfinder 
	sh scripts/plasmidfinder.sh $flye_consensus $flye_plasfinder $db_plasm > "$log_dir/plasmidfinder_flye.log" 2>&1

	# AMRFinderPlus on consensus
	echo "AMRFinderPlus on consensus..."
	flye_amrfinder=$flye_dir/"${sample}"_flye_amrf.tsv
	sh scripts/amrfinderplus.sh $flye_consensus $flye_amrfinder $db_amrf $species_flye_file $threads > "$log_dir/amrfinder_flye.log" 2>&1

	# ResFinder on consensus
	echo "ResFinder on consensus..."
	flye_resfinder=$flye_dir/resfinder
	sh scripts/resfinder.sh $flye_consensus $flye_resfinder $db_res > "$log_dir/resfinder_flye.log" 2>&1
	
	# Collecting results
	cp $flye_consensus $results_dir/Consensus/"$sample"_flye.fasta
	cp $flye_mlst $results_dir/MLST/"$sample"_flye.tsv
	cp -r $flye_plasfinder $results_dir/PlasmidFinder/"$sample"_flye
	cp -r $flye_resfinder $results_dir/ResFinder/"$sample"_flye
	cp $flye_amrfinder $results_dir/AMRFinderPlus/"$sample"_flye.tsv	

done

