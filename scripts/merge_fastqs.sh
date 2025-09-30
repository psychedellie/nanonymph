#!/usr/bin/env bash
set -euo pipefail

# scripts/merge_fastqs.sh
# Merge ONT FASTQs by barcode, filtered by CSV (Lab_ID, Index).
# Usage: scripts/merge_fastqs.sh <input_dir> <output_dir> <sample_sheet.csv>

input_dir=$1
output_dir=$2
sample_sheet=$3

mkdir -p "$output_dir"

# Validate header (expect Lab_ID in col1 and Index in col3)
header=$(head -n1 "$sample_sheet" | tr -d '\r')
IFS=, read -r lab_id _ index _ <<< "$header"
lc1=$(echo "$lab_id" | tr '[:upper:]' '[:lower:]')
lc2=$(echo "$index" | tr '[:upper:]' '[:lower:]')
if [[ "$lc1" != "lab_id" || "$lc2" != "index" ]]; then
  echo "ERROR: Sample sheet must have Lab_ID in first column and Index in third"
  exit 1
fi

# Check for duplicate Lab_IDs
dups=$(tail -n +2 "$sample_sheet" | cut -d, -f1 | sort | uniq -d)
if [ -n "$dups" ]; then
  echo "ERROR: Duplicate Lab_IDs in sample sheet:"
  echo "$dups" | sed 's/^/  - /'
  exit 1
fi

# Merge loop: use col1 (Lab_ID) and col3 (Index)
tail -n +2 "$sample_sheet" | while IFS=, read -r isolate _ barcode _; do
  barcode="$(echo "$barcode" | xargs)"
  isolate="$(echo "$isolate" | xargs)"
  [ -z "$barcode" ] && continue

  src1="$input_dir/$barcode"
  src2="$input_dir/barcode$barcode"
  if [ -d "$src1" ]; then
    src_dir="$src1"
  elif [ -d "$src2" ]; then
    src_dir="$src2"
  else
    echo "WARN: No folder for barcode $barcode"
    continue
  fi

  shopt -s nullglob
  files=( "$src_dir"/*.fastq.gz "$src_dir"/*.fq.gz )
  shopt -u nullglob
  [ ${#files[@]} -eq 0 ] && { echo "WARN: No FASTQs in $src_dir"; continue; }

  out="$output_dir/${isolate}.fastq.gz"
  printf "%s\n" "${files[@]}" | sort -V | xargs -r cat -- > "$out"

  if command -v zcat >/dev/null 2>&1; then
    reads=$(zcat "$out" | awk 'NR%4==1{c++} END{print c+0}')
    echo "OK: $barcode -> $out ($reads reads)"
  else
    echo "OK: $barcode -> $out"
  fi
done
