#!/usr/bin/env bash
set -euo pipefail

# scripts/merge_fastqs.sh
# Merge ONT FASTQs by barcode, filtered by CSV (barcode,isolate_id).
# Usage: scripts/merge_fastqs.sh <input_dir> <output_dir> <sample_sheet.csv>

input_dir=$1
output_dir=$2
sample_sheet=$3

mkdir -p "$output_dir"

# Validate header
header=$(head -n1 "$sample_sheet" | tr -d '\r')
IFS=, read -r col1 col2 <<< "$header"
lc1=$(echo "$col1" | tr '[:upper:]' '[:lower:]')
lc2=$(echo "$col2" | tr '[:upper:]' '[:lower:]')
if [[ "$lc1" != "barcode" || "$lc2" != "isolate_id" ]]; then
  echo "ERROR: Sample sheet must have header: barcode,isolate_id"
  exit 1
fi

# Check for duplicate isolate_ids
dups=$(tail -n +2 "$sample_sheet" | cut -d, -f2 | sort | uniq -d)
if [ -n "$dups" ]; then
  echo "ERROR: Duplicate isolate IDs in sample sheet:"
  echo "$dups" | sed 's/^/  - /'
  exit 1
fi

# Merge loop
tail -n +2 "$sample_sheet" | while IFS=, read -r barcode isolate || [ -n "$barcode$isolate" ]; do
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
