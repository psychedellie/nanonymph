#!/bin/bash

db_root=$1
type=$2

# Check for micromamba
if ! command -v micromamba >/dev/null 2>&1; then
    echo "Error: micromamba not found. Please install micromamba or add it to your PATH." >&2
    exit 1
fi

# Download Bakta DB using micromamba
micromamba run -n bakta bakta_db download --output "$db_root" --type "$type"

# Normalize the folder name to "bakta"
if [ -d "$db_root/db-light" ]; then
    mv "$db_root/db-light" "$db_root/bakta"
elif [ -d "$db_root/db-full" ]; then
    mv "$db_root/db-full" "$db_root/bakta"
fi
