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
db_plasm=$db_root/plasmidfinder/blast  # Path to the PlasmidFinder database
db_res=$db_root/resfinder/blast  # Path to the ResFinder database
db_point=$db_root/pointfinder/blast  # Path to the PointFinder database
db_disinf=$db_root/disinfinder/blast  # Path to the Disinfinder database
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
for np_raw_file in $(find $input_dir -iname "*.fastq.gz" -maxdepth 1) ; do
   	# Extract the sample name without the .fastq.gz extension
	sample=$(basename "$np_raw_file" .fastq.gz)

	echo $sample
	
	# Assemblying with Flye
	echo "Assemblying with Flye..."
	flye_dir=$output_dir/flye/$sample
	flye_assembly=$flye_dir/assembly.fasta
	if [ ! -f $flye_assembly ];then
	  mkdir -p "$flye_dir"  # Ensure the directory exists
	  sh scripts/flye.sh $np_raw_file $flye_dir $threads
	else
	  echo "Assembly file detected, skipping assembly: $flye_assembly"
	fi

	# Assemblying with unicycler
	echo "Assemblying with unicycler..."
	unicycler_dir=$output_dir/unicycler/$sample
	unicycler_assembly=$unicycler_dir/assembly.fasta
	if [ ! -f $unicycler_assembly ];then
	  mkdir -p "$unicycler_dir"  # Ensure the directory exists
	  sh scripts/unicycler_lr.sh $np_raw_file $unicycler_dir $threads
	else
	  echo "Assembly file detected, skipping assembly: $unicycler_assembly"
	fi

	# Polishing Flye assemblies
	echo "Polishing Flye assemblies..."
	flye_medaka=$flye_dir/medaka
	flye_consensus=$flye_medaka/consensus.fasta
	if [ ! -f $flye_consensus ]; then
	  mkdir -p "$flye_medaka"  # Ensure the directory exists
	  sh scripts/medaka.sh $np_raw_file $flye_medaka $flye_assembly
	else
	  echo "Consensus file detected, skipping polishing: $flye_consensus"
	fi

	# Polishing unicycler assemblies
	echo "Polishing unicycler assemblies..."
	unicycler_medaka=$unicycler_dir/medaka
	unicycler_consensus=$unicycler_medaka/consensus.fasta
	if [ ! -f $unicycler_consensus ]; then
	  mkdir -p "$unicycler_medaka"  # Ensure the directory exists
	  sh scripts/medaka.sh $np_raw_file $unicycler_medaka $unicycler_assembly
	else
	  echo "Consensus file detected, skipping polishing: $unicycler_consensus"
	fi

    	# Annotation with Prokka on Flye consensus
    	echo "Annotating Flye consensus with Prokka..."
    	flye_prokka_dir=$flye_dir/prokka
    	sh scripts/prokka.sh $flye_consensus $flye_prokka_dir $sample
    	
    	# Annotation with Prokka on Unicycler consensus
    	echo "Annotating Unicycler consensus with Prokka..."
	unicycler_prokka_dir=$unicycler_dir/prokka
    	sh scripts/prokka.sh $unicycler_consensus $unicycler_prokka_dir $sample
    
	# rMLST on Flye consensus
	echo "Performing rMLST on Flye consensus..."
	species_flye_file=$flye_dir/$sample.species
	flye_rmlst=$flye_dir/"${sample}"_flye_rmlst.tsv
	sh scripts/run_rmlst.sh $flye_consensus $flye_rmlst $organism_file $species_flye_file scripts

	# rMLST on Unicycler consensus
	echo "Performing rMLST on Unicycler consensus..."
	species_unicycler_file=$unicycler_dir/$sample.species
	unicycler_rmlst=$unicycler_dir/"${sample}"_unicycler_rmlst.tsv
	sh scripts/run_rmlst.sh $unicycler_consensus $unicycler_rmlst $organism_file $species_unicycler_file scripts

	# MLST on Flye consensus
	echo "Performing MLST on Flye consensus..."
	flye_mlst=$flye_dir/mlst.tsv
	sh scripts/mlst.sh $flye_consensus $flye_mlst $sample

	# MLST on Unicycler consensus
	echo "Performing MLST on Unicycler consensus..."
	unicycler_mlst=$unicycler_dir/mlst.tsv
	sh scripts/mlst.sh $unicycler_consensus $unicycler_mlst $sample

	# PlasmidFinder on Flye consensus
	echo "PlasmidFinder on Flye consensus..."
	flye_plasfinder=$flye_dir/plasmidfinder
	sh scripts/plasmidfinder.sh $flye_consensus $flye_plasfinder $db_plasm

	# PlasmidFinder on Unicycler consensus
	echo "PlasmidFinder on Unicycler consensus..."
	unicycler_plasfinder=$unicycler_dir/plasmidfinder
	sh scripts/plasmidfinder.sh $unicycler_consensus $unicycler_plasfinder $db_plasm

	# AMRFinderPlus on Flye consensus
	echo "AMRFinderPlus on Flye consensus..."
	flye_amrfinder=$flye_dir/"${sample}"_flye_amrf.tsv
	sh scripts/amrfinderplus.sh $flye_consensus $flye_amrfinder $db_amrf $species_flye_file

	# AMRFinderPlus on Unicycler consensus
	echo "AMRFinderPlus on Unicycler consensus..."
	unicycler_amrfinder=$unicycler_dir/"${sample}"_unicycler_amrf.tsv
	sh scripts/amrfinderplus.sh $unicycler_consensus $unicycler_amrfinder $db_amrf $species_unicycler_file

	# ResFinder on Flye consensus
	echo "ResFinder on Flye consensus..."
	flye_resfinder=$flye_dir/resfinder
	sh scripts/resfinder.sh $flye_consensus $flye_resfinder $db_res $db_point $db_disinf

	# ResFinder on Unicycler consensus
	echo "ResFinder on Unicycler consensus..."
	unicycler_resfinder=$unicycler_dir/resfinder
	sh scripts/resfinder.sh $unicycler_consensus $unicycler_resfinder $db_res $db_point $db_disinf
	
	# Collecting results
	ln -s $flye_consensus $results_dir/Consensus/"$sample"_flye.fasta
	ln -s $unicycler_consensus $results_dir/Consensus/"$sample"_uc.fasta
	ln -s $flye_mlst $results_dir/MLST/"$sample"_flye.tsv
	ln -s $unicycler_mlst $results_dir/MLST/"$sample"_uc.tsv
	ln -s $flye_plasfinder $results_dir/PlasmidFinder/"$sample"_flye
	ln -s $unicycler_plasfinder $results_dir/PlasmidFinder/"$sample"_uc
	ln -s $flye_resfinder $results_dir/ResFinder/"$sample"_flye
	ln -s $unicycler_resfinder $results_dir/ResFinder/"$sample"_uc
	ln -s $flye_amrfinder $results_dir/AMRFinderPlus/"$sample"_flye.tsv
	ln -s $unicycler_amrfinder $results_dir/AMRFinderPlus/"$sample"_uc.tsv
	
done

