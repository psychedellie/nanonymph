#!/bin/bash

# Set default values for optional arguments
threads=4  # Default number of threads if not provided

# Initialize variables for required arguments (these must be passed by the user)
input_dir=""
output_dir=""
basecaller=""
db_root=""
sample_sheet=""   # [EXTRA] Sample sheet CSV with barcode,isolate_id

# Parse arguments passed to the script
# -d: Path to the database root (optional)
# -i: Path to the input directory (required)
# -o: Path to the output directory (required)
# -t: Number of threads to use (optional)
# -m: Basecaller model (optional)
# -s: Sample sheet CSV with headers: barcode,isolate_id   [EXTRA]
while getopts ":d:i:o:t:m:s:" option; do
    case $option in
        d) db_root=$OPTARG;;          # Set database directory
        i) input_dir=$OPTARG;;        # Set input directory
        o) output_dir=$OPTARG;;       # Set output directory
        t) threads=$OPTARG;;          # Override default threads if provided
        m) basecaller=$OPTARG;;       # Set basecaller model
        s) sample_sheet=$OPTARG;;     # [EXTRA] Set sample sheet
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1;;
        :)  echo "Option -$OPTARG requires an argument." >&2; exit 1;;
    esac
done

# Ensure required arguments are provided
# (basecaller is OPTIONAL; threads has a default)
if [ -z "$db_root" ] || [ -z "$input_dir" ] || [ -z "$output_dir" ]; then
    echo "Usage: $0 -d <db_root> -i <input_dir> -o <output_dir> [-s <sample_sheet.csv>] [-t <threads>] [-m <basecaller_model>]"
    echo "  -d: Path to the database root (required)"
    echo "  -i: Path to the input directory (required)"
    echo "  -o: Path to the output directory (required)"
    echo "  -s: CSV file with barcode,isolate_id (optional but recommended)"   # [EXTRA]
    echo "  -t: Number of threads to use (optional, default: $threads)"
    echo "  -m: Basecaller model (optional)"
    exit 1
fi

# ------------------------------
# [EXTRA] Call merge script if sample_sheet provided
# ------------------------------
if [ -n "$sample_sheet" ]; then
  merged_dir="$output_dir/reads_merged"
  mkdir -p "$merged_dir"
  echo "[merge] Running scripts/merge_fastqs.sh on $sample_sheet..."
  scripts/merge_fastqs.sh "$input_dir" "$merged_dir" "$sample_sheet"
  input_dir="$merged_dir"
fi
# ------------------------------

# Print the configuration to verify the arguments being used
echo "=============================="
echo "Configuration:"
echo "Database Root:      $db_root"
echo "Input Directory:    $input_dir"
echo "Output Directory:   $output_dir"
echo "Threads:            $threads"
echo "Basecaller Model:   $basecaller"
echo "=============================="

# Define paths for the databases
db_plasm="$db_root/plasmidfinder"
db_bakta="$db_root/bakta"

# Path to the file that contains supported organism information
organism_file="scripts/config/supported_organisms.yaml"

# Define result directories
results_dir="$output_dir/Results"
consensus_dir="$results_dir/Fasta"
mlst_dir="$results_dir/MLST"
plasmidfinder_dir="$results_dir/PlasmidFinder"
amrfinder_dir="$results_dir/AMRFinderPlus"        
fastplong_dir="$output_dir/fastplong"
filtered_outdir="$fastplong_dir/filtered_reads"
bakta_dir="$results_dir/Bakta"
rmlst_dir="$results_dir/rMLST"
quast_dir="$results_dir/QUAST"

# Create result directories
mkdir -p "$consensus_dir" "$mlst_dir" "$plasmidfinder_dir" "$amrfinder_dir" "$filtered_outdir" "$bakta_dir" "$rmlst_dir" "$quast_dir"

# Skip fastplong if filtered reads already exist
if find "$filtered_outdir" -maxdepth 1 -iname "*.fastq.gz" | read -r _; then
  echo "Filtered reads detected in $filtered_outdir — skipping fastplong."
else
  # Run fastplong
  bash scripts/fastplong.sh $input_dir $fastplong_dir $threads > "$fastplong_dir/fastplong.log" 2>&1
fi

# Move any produced fastqs into filtered_outdir (dest must be a directory)
if compgen -G "$fastplong_dir/*.fastq.gz" > /dev/null; then
  mv "$fastplong_dir"/*.fastq.gz "$filtered_outdir"/
fi

# Loop through all .fastq.gz files in filtered reads directory
for np_raw_file in $(find "$filtered_outdir" -maxdepth 1 -iname "*.fastq.gz"); do
    # Extract the sample name (your fastplong outputs use .hq.fastq.gz)
    sample=$(basename "$np_raw_file" .hq.fastq.gz)
    echo "$sample"

    # Create log directory for each sample
    log_dir="$output_dir/logs/$sample"
    mkdir -p "$log_dir"

    # Assembly with Flye
    echo "Assemblying with Flye..."
    flye_dir="$output_dir/flye/$sample"
    flye_assembly="$flye_dir/assembly.fasta"
    if [ ! -f "$flye_assembly" ]; then
      mkdir -p "$flye_dir"
      sh scripts/flye.sh "$np_raw_file" "$flye_dir" "$threads" > "$log_dir/flye.log" 2>&1
    else
      echo "Assembly file detected, skipping assembly: $flye_assembly"
    fi

    # Polishing assemblies
    echo "Polishing assemblies..."
    flye_medaka="$flye_dir/medaka"
    flye_consensus="$flye_medaka/consensus.fasta"
    if [ ! -f "$flye_consensus" ]; then
      mkdir -p "$flye_medaka"
      sh scripts/medaka.sh "$np_raw_file" "$flye_medaka" "$flye_assembly" "$threads" > "$log_dir/medaka.log" 2>&1
    else
      echo "Consensus file detected, skipping polishing: $flye_consensus"
    fi

    # Annotation with Bakta
    echo "Annotating consensus with Bakta..."
    flye_bakta_dir="$flye_dir/bakta"
    if [ -d "$flye_bakta_dir" ] && [ -n "$(ls -A "$flye_bakta_dir" 2>/dev/null)" ]; then
      echo "Bakta output detected, skipping: $flye_bakta_dir"
    else
      sh scripts/bakta.sh "$flye_consensus" "$flye_bakta_dir" "$sample" "$threads" "$db_bakta" > "$log_dir/bakta.log" 2>&1
    fi

    # QUAST
    echo "QUAST creating report..."
    flye_quast_dir="$flye_dir/quast"
    if [ -d "$flye_quast_dir" ] && [ -n "$(ls -A "$flye_quast_dir" 2>/dev/null)" ]; then
      echo "QUAST output detected, skipping: $flye_quast_dir"
    else
      sh scripts/quast.sh "$flye_consensus" "$flye_quast_dir" "$np_raw_file" "$threads" > "$log_dir/quast.log" 2>&1
    fi

    # rMLST
    echo "Performing rMLST on consensus..."
    species_ONT_file="$flye_dir/$sample.species"
    flye_rmlst="$flye_dir/${sample}_ONT_rmlst.tsv"
    if [ -s "$flye_rmlst" ] && [ -s "$species_ONT_file" ]; then
      echo "rMLST outputs detected, skipping: $flye_rmlst and $species_ONT_file"
    else
      sh scripts/run_rmlst.sh "$flye_consensus" "$flye_rmlst" "$organism_file" "$species_ONT_file" scripts > "$log_dir/rmlst.log" 2>&1
    fi

    # MLST
    echo "Performing MLST on consensus..."
    flye_mlst="$flye_dir/mlst.tsv"
    if [ -s "$flye_mlst" ]; then
      echo "MLST output detected, skipping: $flye_mlst"
    else
      sh scripts/mlst.sh "$flye_consensus" "$flye_mlst" "$sample" > "$log_dir/mlst.log" 2>&1
    fi

    # PlasmidFinder
    echo "PlasmidFinder on consensus..."
    flye_plasfinder="$flye_dir/plasmidfinder"
    if [ -d "$flye_plasfinder" ] && [ -n "$(ls -A "$flye_plasfinder" 2>/dev/null)" ]; then
      echo "PlasmidFinder output detected, skipping: $flye_plasfinder"
    else
      sh scripts/plasmidfinder.sh "$flye_consensus" "$flye_plasfinder" "$db_plasm" > "$log_dir/plasmidfinder.log" 2>&1
    fi

    # AMRFinderPlus
    echo "AMRFinderPlus on consensus..."
    flye_amrfinder="$flye_dir/${sample}_ONT_amrf.txt"
    if [ -s "$flye_amrfinder" ]; then
      echo "AMRFinderPlus output detected, skipping: $flye_amrfinder"
    else
      sh scripts/amrfinderplus.sh "$flye_consensus" "$flye_amrfinder" "$species_ONT_file" "$threads" > "$log_dir/amrfinder.log" 2>&1
    fi

    # Collect results
    cp "$flye_consensus" "$consensus_dir/${sample}_ONT.fasta"
    cp "$flye_mlst" "$mlst_dir/${sample}_ONT.tsv"
    cp -r "$flye_plasfinder/results_tab.tsv" "$plasmidfinder_dir/${sample}_ONT.tsv"
    cp "$flye_amrfinder" "$amrfinder_dir/${sample}_ONT.txt"
    cp -r "$flye_bakta_dir/$sample.tsv" "$bakta_dir/${sample}_ONT.tsv"
    cp -r "$flye_quast_dir/transposed_report.tsv" "$quast_dir/${sample}_ONT.tsv"
    cp -r "$flye_rmlst" "$rmlst_dir/${sample}_ONT.tsv"
done

# Skip report generation if an AMRFinderPlus HTML already exists
if ls "$results_dir/AMRFinderPlus"/*.html >/dev/null 2>&1; then
  echo "AMRFinderPlus HTML report already present — skipping report generation."
else
  bash scripts/generate_html.sh "$results_dir/AMRFinderPlus"
fi

