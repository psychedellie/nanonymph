# Nanonymph

This repository contains a workflow for processing Nanopore sequencing data, including assembly, polishing, annotation, and various analyses for AMR identification.

## Table of Contents

- [Installation](https://www.w3schools.com/html/tryit.asp?filename=tryhtml_editor#installation)
- [Usage](https://www.w3schools.com/html/tryit.asp?filename=tryhtml_editor#usage)
- [Workflow Steps](https://www.w3schools.com/html/tryit.asp?filename=tryhtml_editor#workflow-steps)

## Installation

Clone the repository and navigate to the directory:

```
git clone https://github.com/psychedellie/nanonymph.git
cd nanonymph
```
**Note:** All scripts in this workflow are designed to work with **micromamba**. Ensure you have micromamba installed at `~/.local/bin/micromamba`.

### Setting Up Environments

Use the provided `environments_setup.sh` script to create environments for each tool. Place your YAML files in the `envs` directory and run the script:

```
./environments_setup.sh
```

### Setting Up Databases

Use the provided `databases_setup.sh` script to set up the necessary databases. This script will create a `databases` directory and run setup scripts for each database:

```
./databases_setup.sh
```

## Usage

To run the workflow, use the following command:

```
./wf_nanopore.sh -d  -i  -o  -t
```

### Arguments

- `-d`: Path to the database root (required)
- `-i`: Path to the input directory containing FASTQ files (required)
- `-o`: Path to the output directory (required)
- `-t`: Number of threads to use (optional, default: 3)

## Workflow Steps

1.  **Assembly**:
    - **Flye**: Assembles the raw reads.
    - **Unicycler**: Assembles the raw reads.
2.  **Polishing**:
    - **Medaka**: Polishes the assemblies from Flye and Unicycler.
3.  **Annotation**:
    - **Prokka**: Annotates the polished assemblies.
4.  **Typing and Analysis**:
    - **rMLST**: Performs ribosomal MLST on the consensus sequences.
    - **MLST**: Performs MLST on the consensus sequences.
    - **PlasmidFinder**: Identifies plasmids in the consensus sequences.
    - **AMRFinderPlus**: Detects antimicrobial resistance genes (organism-specific mode; providing point mutations for organisms included in AMRFinderPlus' dictionary).
    - **ResFinder**: Identifies resistance genes using ResFinder.
