#!/bin/bash

# Directory where your YAML files are stored
env_dir="envs"

# Loop over each YAML file in the specified directory
for file in "$env_dir"/*.yaml; do
  echo "Creating environment from $file"
  micromamba env create -f "$file" -y
done
