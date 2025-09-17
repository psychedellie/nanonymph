#!/bin/bash

#Create database directory if it doesn't exist
mkdir -p databases

#Set default database
db_root=databases

#Run setup for each database
sh scripts/plasmidfinder_setup.sh $db_root