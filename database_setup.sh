#!/bin/bash

bakta_db_type=""
db_root=""

while getopts ":t:d:" option; do
    case $option in
        t) bakta_db_type=$OPTARG;;  	# Bakta DB type
        d) db_root=$OPTARG;;           # Database root directory
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1;;
        :) echo "Option -$OPTARG requires an argument." >&2; exit 1;;
    esac
done

# Ensure Bakta type is provided
if [ -z "$bakta_db_type" ]; then
    echo "Usage: $0 -t <bakta_db_type> [-d <db_root>]"
    exit 1
fi

# Create database directory if it doesn't exist
mkdir -p "$db_root"

# Print configuration
echo "=============================="
echo "Bakta DB Type:     $bakta_db_type"
echo "Database Root:     $db_root"
echo "=============================="

# Run setup scripts
sh scripts/plasmidfinder_setup.sh $db_root
sh scripts/bakta_setup.sh $db_root $bakta_db_type
