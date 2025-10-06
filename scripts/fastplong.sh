#!/usr/bin/env bash
set -euo pipefail
[ $# -lt 3 ] && { echo "usage: $0 <input_dir> <output_dir> <threads>"; exit 2; }

input_dir=$1; output_dir=$2; threads=$3
mkdir -p "$output_dir"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RUNNER="micromamba run -n fastplong"
command -v micromamba >/dev/null 2>&1 && RUNNER="micromamba run -n fastplong"

$RUNNER bash -lc 'command -v fastplong' >/dev/null || {
  echo "fastplong not found in env 'fastplong'"; exit 1; }

$RUNNER python $script_dir/parallel.py \
  --input_dir $input_dir --out_dir $output_dir --thread $threads --args '-f 10 -t 10 -m 10'
